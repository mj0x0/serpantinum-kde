// khdump — dump KDE's holiday + astronomical-event data as JSON.
//
// KHolidays ships its region data COMPILED INTO libKF6Holidays (2714 rules, 170
// regions) rather than as files on disk, and the org.kde.kholidays QML module
// only exposes a region *picker* model — no way to query events. So this tiny
// tool bridges the gap: it links the real library and prints JSON that the
// Calendar popup can read like any other helper.
//
// rawHolidaysWithAstroSeasons() is what KDE's own calendar plugin uses, so we
// get public holidays, religious/cultural days AND equinoxes/solstices together.
//
// Build: ./build.sh    Usage:
//   khdump --regions
//   khdump --holidays <regionCode> <YYYY-MM-DD> <YYYY-MM-DD>
//   khdump --month    <regionCode> <YYYY-MM>

#include <QCoreApplication>
#include <QDate>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>
#include <KHolidays/HolidayRegion>
#include <KHolidays/Holiday>
#include <KHolidays/LunarPhase>

// rawHolidaysWithAstroSeasons() covers holidays plus SOLSTICES/EQUINOXES only —
// AstroSeasons and LunarPhase are separate classes in KHolidays, so moon phases
// have to be walked day by day and merged in ourselves.
static QJsonArray dump(const QString &code, const QDate &from, const QDate &to, bool moon, bool astro)
{
    KHolidays::HolidayRegion region(code);
    QJsonArray arr;
    if (region.isValid()) {
        const auto holidays = astro ? region.rawHolidaysWithAstroSeasons(from, to)
                                    : region.rawHolidays(from, to);
        for (const auto &h : holidays) {
            QJsonObject o;
            o["date"] = h.observedStartDate().toString(Qt::ISODate);
            o["name"] = h.name();
            o["categories"] = QJsonArray::fromStringList(h.categoryList());
            arr.append(o);
        }
    }

    if (moon) {
        for (QDate d = from; d <= to; d = d.addDays(1)) {
            // Only the four principal phases land on a specific day; the
            // intermediate ones would mark nearly every date, which is noise.
            const auto ph = KHolidays::LunarPhase::phaseAtDate(d);
            if (ph != KHolidays::LunarPhase::NewMoon
                && ph != KHolidays::LunarPhase::FirstQuarter
                && ph != KHolidays::LunarPhase::LastQuarter
                && ph != KHolidays::LunarPhase::FullMoon)
                continue;
            QJsonObject o;
            o["date"] = d.toString(Qt::ISODate);
            o["name"] = KHolidays::LunarPhase::phaseName(ph);
            o["categories"] = QJsonArray{QStringLiteral("lunar")};
            arr.append(o);
        }
    }
    return arr;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTextStream out(stdout);
    const QStringList a = app.arguments();

    if (a.size() >= 2 && a[1] == QLatin1String("--regions")) {
        QJsonArray arr;
        for (const QString &c : KHolidays::HolidayRegion::regionCodes()) {
            QJsonObject o;
            o["code"] = c;
            o["name"] = KHolidays::HolidayRegion::name(c);
            arr.append(o);
        }
        out << QJsonDocument(arr).toJson(QJsonDocument::Compact) << "\n";
        return 0;
    }

    const bool moon = a.contains(QLatin1String("--moon"));
    // Seasons ride along with the holidays unless asked to stay out.
    const bool astro = !a.contains(QLatin1String("--no-astro"));

    if (a.size() >= 5 && a[1] == QLatin1String("--holidays")) {
        out << QJsonDocument(dump(a[2],
                                  QDate::fromString(a[3], Qt::ISODate),
                                  QDate::fromString(a[4], Qt::ISODate), moon, astro))
                   .toJson(QJsonDocument::Compact) << "\n";
        return 0;
    }

    // --month YYYY-MM → whole month, so the Calendar can fetch one page at a time.
    if (a.size() >= 4 && a[1] == QLatin1String("--month")) {
        const QDate first = QDate::fromString(a[3] + QLatin1String("-01"), Qt::ISODate);
        if (!first.isValid()) {
            out << "[]\n";
            return 0;
        }
        out << QJsonDocument(dump(a[2], first, first.addMonths(1).addDays(-1), moon, astro))
                   .toJson(QJsonDocument::Compact) << "\n";
        return 0;
    }

    out << "usage: khdump --regions | --holidays <code> <from> <to> [--moon] [--no-astro]"
           " | --month <code> <YYYY-MM> [--moon] [--no-astro]\n";
    return 1;
}
