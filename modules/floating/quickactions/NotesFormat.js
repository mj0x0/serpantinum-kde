.pragma library

function escapeHtml(t) {
    return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function formatInlineMarkdown(text, colors) {
    if (!text) return "";
    var c = colors || {};
    // no colour -> omit the attribute so the run inherits the Text item's colour
    var codeAttr = c.code ? " color=\"" + c.code + "\"" : "";
    var linkAttr = c.link ? " color=\"" + c.link + "\"" : "";
    var s = text;
    // Links first: a URL may contain * or _, which the emphasis rules below would eat.
    s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g,
                  "<a href=\"$2\"><font" + linkAttr + ">$1</font></a>");
    s = s.replace(/`([^`]+)`/g, "<font" + codeAttr + " face=\"monospace\"><b>$1</b></font>");
    s = s.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
    s = s.replace(/__([^_]+)__/g, "<b>$1</b>");
    s = s.replace(/\*([^*]+)\*/g, "<i>$1</i>");
    s = s.replace(/_([^_]+)_/g, "<i>$1</i>");
    s = s.replace(/~~([^~]+)~~/g, "<s>$1</s>");
    return s;
}

// Direction of the first strong character, so an RTL note can be marked as such.
function isRtlText(s) {
    var strong = /[A-Za-z\u00C0-\u024F\u0370-\u04FF\u0590-\u05FF\u0600-\u07BF\u0860-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/;
    var rtl = /[\u0590-\u05FF\u0600-\u07BF\u0860-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/;
    var m = (s || "").match(strong);
    return !!m && rtl.test(m[0]);
}

function markdownToHtml(md, colors) {
    if (!md) return "";
    var c = colors || {};
    var preStyle = c.codeBg ? " style=\"background-color:" + c.codeBg + ";\"" : "";
    // The glyphs need an explicit face: the UI font has none of the nf-md range.
    var faceAttr = c.iconFont ? " face=\"" + c.iconFont + "\"" : "";
    var undoneColor = c.checkUndone || c.text;
    var doneBoxAttr = (c.checkDone ? " color=\"" + c.checkDone + "\"" : "") + faceAttr;
    var undoneBoxAttr = (undoneColor ? " color=\"" + undoneColor + "\"" : "") + faceAttr;
    // The nf-md glyphs are bidi class L; without this the whole block flips to LTR.
    var dir = isRtlText(md) ? "&#x200F;" : "";
    var lines = md.split("\n");
    var out = [];
    var inCode = false;
    var codeLines = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line.trim().indexOf("```") === 0) {
            if (inCode) {
                out.push("<pre" + preStyle + "><code>" + codeLines.join("<br/>") + "</code></pre>");
                codeLines = [];
                inCode = false;
            } else {
                inCode = true;
                codeLines = [];
            }
            continue;
        }
        var esc = escapeHtml(line);
        if (inCode) {
            codeLines.push(esc);
            continue;
        }
        if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) {
            out.push("<hr/>");
        } else if (esc.indexOf("### ") === 0) {
            out.push("<b><font size=\"+1\">" + formatInlineMarkdown(esc.substring(4), c) + "</font></b>");
        } else if (esc.indexOf("## ") === 0) {
            out.push("<b><font size=\"+2\">" + formatInlineMarkdown(esc.substring(3), c) + "</font></b>");
        } else if (esc.indexOf("# ") === 0) {
            out.push("<b><font size=\"+3\">" + formatInlineMarkdown(esc.substring(2), c) + "</font></b>");
        } else if (/^\s*[-*+]\s+\[[ xX]\]/.test(esc)) {
            // href carries the source line, so the view can toggle it; i still tracks the
            // original line because fenced blocks `continue` rather than shifting the index.
            var box = esc.match(/^\s*[-*+]\s+\[([ xX])\]\s?/);
            var rest = esc.replace(/^\s*[-*+]\s+\[[ xX]\]\s?/, "");
            var isDone = box[1] !== " ";
            var body = formatInlineMarkdown(rest, c);
            if (isDone) {
                // <s> outside the colour so inner runs keep their own; outside the anchor so
                // the rule does not cross the check glyph.
                body = c.doneText ? "<s><font color=\"" + c.doneText + "\">" + body + "</font></s>"
                                  : "<s>" + body + "</s>";
            }
            // The box is a link only so it can be clicked; style it back into plain text.
            out.push(dir + "&nbsp;&nbsp;<a href=\"chk:" + i + "\" style=\"text-decoration:none;\"><font"
                     + (isDone ? doneBoxAttr : undoneBoxAttr) + ">"
                     + (isDone ? "&#xF0133;" : "&#xF0130;") + "</font></a>&nbsp;&nbsp;" + body);
        } else if (/^\s*[-*+]\s+/.test(esc)) {
            var item = esc.replace(/^\s*[-*+]\s+/, "");
            out.push("&nbsp;&nbsp;• " + formatInlineMarkdown(item, c));
        } else if (/^\s*\d+\.\s+/.test(esc)) {
            var m = esc.match(/^(\s*\d+\.)\s+(.*)$/);
            out.push("&nbsp;&nbsp;" + (m ? m[1] + " " + formatInlineMarkdown(m[2], c) : esc));
        } else if (/^\s*>\s?/.test(line)) {
            // Tested against the raw line: escaping turns "> " into "&gt; " first.
            out.push("<i>│ " + formatInlineMarkdown(escapeHtml(line.replace(/^\s*>\s?/, "")), c) + "</i>");
        } else {
            out.push(formatInlineMarkdown(esc, c));
        }
    }
    if (inCode && codeLines.length > 0) {
        out.push("<pre" + preStyle + "><code>" + codeLines.join("<br/>") + "</code></pre>");
    }
    // <hr/> is a block element, so the joining breaks either side double its spacing.
    return out.join("<br/>").replace(/(<br\/>)?<hr\/>(<br\/>)?/g, "<hr/>");
}

// Flip the [ ] / [x] on one source line. Returns the new text, or null if that line is
// not a checkbox, so the caller can leave the note untouched.
function toggleCheckboxLine(md, index) {
    var lines = (md || "").split("\n");
    if (index < 0 || index >= lines.length) return null;
    var m = lines[index].match(/^(\s*[-*+]\s+\[)([ xX])(\][\s\S]*)$/);
    if (!m) return null;
    lines[index] = m[1] + (m[2] === " " ? "x" : " ") + m[3];
    return lines.join("\n");
}

function formatRelativeTime(timestamp, i18n, timeFormat) {
    if (!timestamp) return "";
    var now = new Date();
    var noteDate = new Date(timestamp);
    var diffSec = Math.floor((now.getTime() - noteDate.getTime()) / 1000);

    var timePart = (timeFormat || "HH:mm").indexOf("hh:") !== -1
        ? Qt.formatDateTime(noteDate, "hh:mm AP")
        : Qt.formatDateTime(noteDate, "HH:mm");

    if (diffSec < 60) return i18n.t("datetime.just_now");

    var diffMin = Math.floor(diffSec / 60);
    if (diffMin < 60) return i18n.t("datetime.minutes_ago", { mins: diffMin });

    var isSameDay = now.getFullYear() === noteDate.getFullYear() &&
                    now.getMonth() === noteDate.getMonth() &&
                    now.getDate() === noteDate.getDate();

    var yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    var isYesterday = yesterday.getFullYear() === noteDate.getFullYear() &&
                      yesterday.getMonth() === noteDate.getMonth() &&
                      yesterday.getDate() === noteDate.getDate();

    var diffDays = Math.floor(diffSec / 86400);

    if (isSameDay) return timePart;
    if (isYesterday) return i18n.t("datetime.yesterday", { time: timePart });
    if (diffDays < 7) return Qt.formatDateTime(noteDate, "dddd") + " " + timePart;
    return Qt.formatDateTime(noteDate, "yyyy-MM-dd ") + timePart;
}

function formatPreciseTime(timestamp) {
    if (!timestamp) return "";
    return Qt.formatDateTime(new Date(timestamp), "yyyy-MM-dd HH:mm:ss");
}
