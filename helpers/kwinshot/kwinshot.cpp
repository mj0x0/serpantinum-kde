// kwinshot — ask KWin for screen pixels over D-Bus and write them out as a PNG.
//
// The screenshot overlay freezes the screen by launching Spectacle, which costs ~250 ms
// of process startup before a pixel is read. KWin already hands out the compositor's own
// framebuffer on org.kde.KWin.ScreenShot2, so this helper asks for it directly.
//
// KWin writes RAW rows into a pipe we pass it and describes them in the method reply, so
// the call and the read MUST overlap: a frame is megabytes and a pipe buffer is ~64 KB,
// so a blocking call that only read afterwards would wedge both processes. Hence the
// async call and a QSocketNotifier on one event loop.
//
// Pixels come back logical, not native: they line up one-to-one with the overlay's logical
// selection, at the cost of being fewer pixels than Spectacle's file on a scaled output.
//
// The interface is restricted: KWin resolves our pid to an executable and demands an
// installed .desktop carrying X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2.
// Without that grant every call answers NoAuthorized, which gets its own exit code so
// the caller can drop back to Spectacle without a word.
//
// Build: see build_binaries() in install.sh.   Usage:
//   kwinshot --out FILE --geometry "X,Y WxH"   region of the workspace, logical pixels
//   kwinshot --out FILE --full                 the screen the cursor is on (Spectacle -m)
//   kwinshot --out FILE --workspace            every screen, united
//   kwinshot --out FILE --self-test            no D-Bus: a known buffer down the save path
//
// Exit codes:
//   0  wrote the file, and one line of JSON describing it on stdout
//   1  bad arguments
//   2  NoAuthorized — the grant is missing, fall back quietly
//   3  anything else failed (no KWin, D-Bus error, bad or short reply, write failed)

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSocketNotifier>
#include <QTextStream>
#include <QTimer>

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>

namespace {

constexpr int ExitOk = 0;
constexpr int ExitUsage = 1;
constexpr int ExitNoAuth = 2;
constexpr int ExitFailed = 3;

constexpr int CallTimeoutMs = 3000;
constexpr int OverallTimeoutMs = 4000;
// KWin has the frame in hand before it replies, so the pixels are pure pipe throughput
// (~4 ms for 15 MB). Anything slower than this is a truncated frame, which no EOF will
// announce while we still hold a dup of the write end ourselves.
constexpr int PixelTimeoutMs = 1000;
constexpr qsizetype ReadChunk = 1 << 18;
constexpr qint64 ReadCap = qint64(1) << 30;
constexpr uint MaxEdge = 65535;

void say(const QString &line)
{
    QTextStream(stderr) << "kwinshot: " << line << "\n";
}

int usage()
{
    QTextStream(stderr) << "usage: kwinshot --out FILE"
                           " (--geometry \"X,Y WxH\" | --full | --workspace | --self-test)\n";
    return ExitUsage;
}

struct Area {
    int x = 0;
    int y = 0;
    uint w = 0;
    uint h = 0;
};

// "X,Y WxH", the shape helpers/screenshot.sh already speaks. x and y may be negative:
// a second monitor can sit left of or above the origin.
bool parseGeometry(const QString &text, Area *area)
{
    const QStringList halves = text.trimmed().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    if (halves.size() != 2)
        return false;
    const QStringList pos = halves[0].split(QLatin1Char(','));
    const QStringList size = halves[1].toLower().split(QLatin1Char('x'));
    if (pos.size() != 2 || size.size() != 2)
        return false;

    bool okX = false, okY = false, okW = false, okH = false;
    const int x = pos[0].toInt(&okX);
    const int y = pos[1].toInt(&okY);
    const uint w = size[0].toUInt(&okW);
    const uint h = size[1].toUInt(&okH);
    if (!okX || !okY || !okW || !okH)
        return false;
    if (w == 0 || h == 0 || w > MaxEdge || h > MaxEdge)
        return false;

    *area = Area{x, y, w, h};
    return true;
}

// Wrap KWin's raw rows and write the PNG. --self-test drives this same function, so the
// half that cannot be reached without the grant is still covered.
bool saveRaw(const QByteArray &data, const QVariantMap &reply, const QString &outFile,
             QJsonObject *info, QString *why)
{
    if (reply.value(QStringLiteral("type")).toString() != QLatin1String("raw")) {
        *why = QStringLiteral("reply is not a raw image");
        return false;
    }

    bool okW = false, okH = false, okS = false, okF = false;
    const uint w = reply.value(QStringLiteral("width")).toUInt(&okW);
    const uint h = reply.value(QStringLiteral("height")).toUInt(&okH);
    const uint stride = reply.value(QStringLiteral("stride")).toUInt(&okS);
    const uint format = reply.value(QStringLiteral("format")).toUInt(&okF);
    if (!okW || !okH || !okS || !okF) {
        *why = QStringLiteral("reply is missing width/height/stride/format");
        return false;
    }
    if (w == 0 || h == 0 || w > MaxEdge || h > MaxEdge) {
        *why = QStringLiteral("reply describes a %1x%2 image").arg(w).arg(h);
        return false;
    }
    if (format == 0 || format >= uint(QImage::NImageFormats)) {
        *why = QStringLiteral("unknown QImage format %1").arg(format);
        return false;
    }

    const QImage probe(1, 1, QImage::Format(format));
    if (probe.isNull()) {
        *why = QStringLiteral("unsupported QImage format %1").arg(format);
        return false;
    }
    const qint64 rowBytes = (qint64(w) * probe.depth() + 7) / 8;
    const qint64 wanted = qint64(stride) * h;
    if (stride < rowBytes) {
        *why = QStringLiteral("stride %1 does not fit a %2px row of format %3")
                   .arg(stride).arg(w).arg(format);
        return false;
    }
    if (wanted > ReadCap) {
        *why = QStringLiteral("reply describes %1 bytes, over the %2 byte cap")
                   .arg(wanted).arg(ReadCap);
        return false;
    }
    if (data.size() < wanted) {
        *why = QStringLiteral("short read: %1 of %2 bytes").arg(data.size()).arg(wanted);
        return false;
    }

    QImage image(reinterpret_cast<const uchar *>(data.constData()), int(w), int(h),
                 int(stride), QImage::Format(format));
    if (image.isNull()) {
        *why = QStringLiteral("could not wrap %1x%2 of format %3").arg(w).arg(h).arg(format);
        return false;
    }
    // native-resolution is off, so KWin always answers 1.0; carry whatever it says instead
    // of resampling, and let the caller read it back off stdout.
    const double scale = reply.value(QStringLiteral("scale"), 1.0).toDouble();
    if (scale > 0.0)
        image.setDevicePixelRatio(scale);

    // Qt's PNG `quality` runs backwards: 90+ stores uncompressed, 10x the bytes for 8 ms.
    // save(QString) also buries a failed flush in a 16 KiB buffer and still answers true,
    // so the bytes go through QSaveFile and commit() is what reports success.
    QSaveFile out(outFile);
    if (!out.open(QIODevice::WriteOnly)) {
        *why = QStringLiteral("could not open %1: %2").arg(outFile, out.errorString());
        return false;
    }
    if (!image.save(&out, "PNG")) {
        *why = QStringLiteral("PNG encode refused format %1").arg(format);
        return false;
    }
    if (!out.commit()) {
        *why = QStringLiteral("could not write %1: %2").arg(outFile, out.errorString());
        return false;
    }

    info->insert(QStringLiteral("file"), outFile);
    info->insert(QStringLiteral("width"), int(w));
    info->insert(QStringLiteral("height"), int(h));
    info->insert(QStringLiteral("format"), int(format));
    info->insert(QStringLiteral("scale"), scale);
    info->insert(QStringLiteral("bytes"), double(wanted));
    return true;
}

// QDBusUnixFileDescriptor dups the write end, and the pending call holds that dup past
// this function — see why completion counts bytes instead of waiting for EOF in capture().
QDBusPendingCall sendCapture(const QString &method, const QVariantList &leading, int writeFd)
{
    QVariantMap options;
    options.insert(QStringLiteral("include-cursor"), false);
    options.insert(QStringLiteral("native-resolution"), false);
    // Our own windows are the only "caller windows" there are; left on, this would hide
    // the shell's the day something calls CaptureArea from inside quickshell.
    options.insert(QStringLiteral("hide-caller-windows"), false);

    QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
                                                       QStringLiteral("/org/kde/KWin/ScreenShot2"),
                                                       QStringLiteral("org.kde.KWin.ScreenShot2"),
                                                       method);
    QVariantList args = leading;
    args << QVariant(options) << QVariant::fromValue(QDBusUnixFileDescriptor(writeFd));
    call.setArguments(args);
    return QDBusConnection::sessionBus().asyncCall(call, CallTimeoutMs);
}

int capture(const QString &method, const QVariantList &leading, const QString &outFile)
{
    if (!QDBusConnection::sessionBus().isConnected()) {
        say(QStringLiteral("no session bus"));
        return ExitFailed;
    }

    int fds[2];
    if (::pipe2(fds, O_CLOEXEC) != 0) {
        say(QStringLiteral("pipe: %1").arg(QString::fromLocal8Bit(::strerror(errno))));
        return ExitFailed;
    }
    const int readFd = fds[0];
    // Must not fail: a blocking read inside the notifier would hang past every watchdog.
    const int flags = ::fcntl(readFd, F_GETFL);
    if (flags == -1 || ::fcntl(readFd, F_SETFL, flags | O_NONBLOCK) == -1) {
        say(QStringLiteral("fcntl: %1").arg(QString::fromLocal8Bit(::strerror(errno))));
        ::close(readFd);
        ::close(fds[1]);
        return ExitFailed;
    }

    QByteArray data;
    QVariantMap results;
    QString failure;
    int code = ExitFailed;
    bool eof = false, replied = false, ok = false;
    qint64 replyMs = 0, pixelsMs = 0;
    // Bytes the reply promises. EOF cannot be the finish line: QDBusPendingCall keeps the
    // sent message alive, and with it our own dup of the write end, so the pipe never
    // closes from our side. Counting bytes is deterministic anyway.
    qint64 expected = -1;

    QElapsedTimer clock;
    clock.start();
    QDBusPendingCall pending = sendCapture(method, leading, fds[1]);
    ::close(fds[1]);

    QEventLoop loop;
    QSocketNotifier notifier(readFd, QSocketNotifier::Read);
    QDBusPendingCallWatcher watcher(pending);
    QTimer watchdog;

    auto drain = [&]() {
        for (;;) {
            const qsizetype used = data.size();
            if (used >= ReadCap) {
                failure = QStringLiteral("KWin sent more than %1 bytes").arg(ReadCap);
                eof = true;
                return;
            }
            data.resize(used + ReadChunk);
            const ssize_t n = ::read(readFd, data.data() + used, ReadChunk);
            if (n > 0) {
                data.resize(used + n);
                continue;
            }
            data.resize(used);
            if (n == 0) {
                eof = true;
                return;
            }
            if (errno == EINTR)
                continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                return;
            failure = QStringLiteral("read: %1").arg(QString::fromLocal8Bit(::strerror(errno)));
            eof = true;
            return;
        }
    };

    // The frame can only be judged complete once the reply has said how big it is, and
    // KWin blocks writing until we drain, so the reader runs whether or not it has arrived.
    auto maybeFinish = [&]() {
        if (!replied)
            return;
        if (expected < 0 || eof || data.size() >= expected) {
            pixelsMs = clock.elapsed();
            loop.quit();
        }
    };

    QObject::connect(&notifier, &QSocketNotifier::activated, &notifier, [&]() {
        drain();
        if (eof || (expected >= 0 && data.size() >= expected))
            notifier.setEnabled(false);
        maybeFinish();
    });

    QObject::connect(&watcher, &QDBusPendingCallWatcher::finished, &watcher, [&]() {
        replied = true;
        replyMs = clock.elapsed();
        const QDBusPendingReply<QVariantMap> reply(watcher);
        if (reply.isError()) {
            const QDBusError error = reply.error();
            code = error.name() == QLatin1String("org.kde.KWin.ScreenShot2.Error.NoAuthorized")
                       ? ExitNoAuth : ExitFailed;
            failure = error.name() + QLatin1String(": ") + error.message();
            loop.quit();
            return;
        }
        results = reply.value();
        ok = true;
        // KWin answers before it writes, so the whole frame can be reserved up front. A
        // reply that describes nothing sane leaves expected at -1 and saveRaw says why.
        const qint64 wanted = qint64(results.value(QStringLiteral("stride")).toUInt())
                            * results.value(QStringLiteral("height")).toUInt();
        if (wanted > 0 && wanted <= ReadCap) {
            expected = wanted;
            data.reserve(wanted + ReadChunk);
        }
        watchdog.start(PixelTimeoutMs);
        maybeFinish();
    });

    watchdog.setSingleShot(true);
    QObject::connect(&watchdog, &QTimer::timeout, &watchdog, [&]() {
        // With a reply in hand, the checks below name the fault better than a timeout can.
        if (failure.isEmpty() && !ok)
            failure = QStringLiteral("gave up after %1 ms without a reply").arg(OverallTimeoutMs);
        loop.quit();
    });
    watchdog.start(OverallTimeoutMs);

    loop.exec();

    notifier.setEnabled(false);
    ::close(readFd);

    if (!failure.isEmpty()) {
        say(failure);
        return code;
    }
    if (!replied || !ok) {
        say(QStringLiteral("no reply from KWin"));
        return ExitFailed;
    }

    QElapsedTimer saveClock;
    saveClock.start();
    QJsonObject info;
    QString why;
    if (!saveRaw(data, results, outFile, &info, &why)) {
        say(why);
        return ExitFailed;
    }

    info.insert(QStringLiteral("reply_ms"), double(replyMs));
    info.insert(QStringLiteral("pixels_ms"), double(pixelsMs));
    info.insert(QStringLiteral("save_ms"), double(saveClock.elapsed()));
    info.insert(QStringLiteral("total_ms"), double(clock.elapsed()));
    QTextStream(stdout) << QJsonDocument(info).toJson(QJsonDocument::Compact) << "\n";
    return ExitOk;
}

// A known RGBX8888 frame — the format KWin actually produces — fed through saveRaw, so
// the wrap-and-save path can be checked on a machine that has no grant.
int selfTest(const QString &outFile)
{
    constexpr uint w = 640, h = 360;
    constexpr uint stride = w * 4;
    QByteArray data(qsizetype(stride) * h, Qt::Uninitialized);
    for (uint y = 0; y < h; ++y) {
        uchar *row = reinterpret_cast<uchar *>(data.data()) + qsizetype(stride) * y;
        for (uint x = 0; x < w; ++x) {
            uchar *pixel = row + x * 4;
            pixel[0] = uchar(x & 0xff);
            pixel[1] = uchar(y & 0xff);
            pixel[2] = 0x40;
            pixel[3] = 0xff;
        }
    }

    QVariantMap results;
    results.insert(QStringLiteral("type"), QStringLiteral("raw"));
    results.insert(QStringLiteral("width"), quint32(w));
    results.insert(QStringLiteral("height"), quint32(h));
    results.insert(QStringLiteral("stride"), quint32(stride));
    results.insert(QStringLiteral("format"), quint32(QImage::Format_RGBX8888));
    results.insert(QStringLiteral("scale"), 1.0);

    QElapsedTimer saveClock;
    saveClock.start();
    QJsonObject info;
    QString why;
    if (!saveRaw(data, results, outFile, &info, &why)) {
        say(why);
        return ExitFailed;
    }
    info.insert(QStringLiteral("save_ms"), double(saveClock.elapsed()));
    QTextStream(stdout) << QJsonDocument(info).toJson(QJsonDocument::Compact) << "\n";
    return ExitOk;
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QStringList args = app.arguments();

    QString outFile, geometry;
    bool full = false, workspace = false, test = false, sawOut = false, sawGeom = false;

    // A repeated flag is refused rather than letting the last copy win.
    for (int i = 1; i < args.size(); ++i) {
        const QString &arg = args[i];
        if (arg == QLatin1String("--out")) {
            if (sawOut || ++i >= args.size())
                return usage();
            sawOut = true;
            outFile = args[i];
        } else if (arg == QLatin1String("--geometry")) {
            if (sawGeom || ++i >= args.size())
                return usage();
            sawGeom = true;
            geometry = args[i];
        } else if (arg == QLatin1String("--full")) {
            if (full)
                return usage();
            full = true;
        } else if (arg == QLatin1String("--workspace")) {
            if (workspace)
                return usage();
            workspace = true;
        } else if (arg == QLatin1String("--self-test")) {
            if (test)
                return usage();
            test = true;
        } else {
            return usage();
        }
    }

    const int modes = int(!geometry.isEmpty()) + int(full) + int(workspace) + int(test);
    if (modes != 1 || outFile.isEmpty())
        return usage();

    if (test)
        return selfTest(outFile);
    if (full)
        return capture(QStringLiteral("CaptureActiveScreen"), {}, outFile);
    if (workspace)
        return capture(QStringLiteral("CaptureWorkspace"), {}, outFile);

    Area area;
    if (!parseGeometry(geometry, &area)) {
        say(QStringLiteral("bad geometry \"%1\", expected \"X,Y WxH\"").arg(geometry));
        return ExitUsage;
    }
    return capture(QStringLiteral("CaptureArea"),
                   {QVariant(area.x), QVariant(area.y), QVariant(area.w), QVariant(area.h)},
                   outFile);
}
