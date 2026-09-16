---
tags: [claude, dashboard]
---
# 🧭 Claude Dashboard

> Requires the **Dataview** community plugin (Settings → Community plugins →
> Browse → "Dataview" → Install → Enable). Until then these show as code blocks.

## 📌 Active threads
See [[INDEX]] — kept current every session.

## 🕒 Recent sessions
```dataview
TABLE WITHOUT ID file.link AS "Day", file.mtime AS "Updated"
FROM "Claude/Sessions"
SORT file.name DESC
LIMIT 20
```

## ✅ Open follow-ups (anything I wrote as a TODO)
```dataview
TASK
FROM "Claude/Sessions" OR "Claude"
WHERE !completed
```

## 🧠 What Claude remembers about me
```dataview
LIST
FROM "Claude/Memory"
SORT file.name ASC
```

---
*This vault runs itself: sessions auto-log here, context auto-loads into every
Claude session, and everything syncs to both machines. Just work — it keeps up.*
