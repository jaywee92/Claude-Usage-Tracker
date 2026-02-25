# Design: Claude Usage Tracker – Community Fork & Bug Fixes

**Datum:** 2026-02-25
**Projekt:** Fork von https://github.com/hamed-elfayome/Claude-Usage-Tracker
**Ziel:** Kritische Bugs beheben, als eigenen GitHub-Fork veröffentlichen, dabei Swift/macOS-Entwicklung lernen

---

## Kontext

Das Original-Projekt ist eine native macOS Menu-Bar-App (Swift/SwiftUI), die Claude AI Nutzungslimits überwacht. Der Maintainer ist nicht mehr aktiv, es gibt 27 offene Issues und 13 ungemergete PRs.

## Ansatz

Lernorientierter Weg: Xcode & Swift von Grund auf einrichten, Bugs schrittweise analysieren und beheben, dabei Swift-Konzepte erklären.

---

## Phase 1: Entwicklungsumgebung

### Tools
- Xcode 15+ (Mac App Store, ~7 GB)
- Git (in Xcode enthalten)
- GitHub Account

### Schritte
1. Xcode aus dem Mac App Store installieren
2. Original-Repo auf GitHub forken: `github.com/DEIN_USERNAME/Claude-Usage-Tracker`
3. Fork klonen: `git clone git@github.com:DEIN_USERNAME/Claude-Usage-Tracker.git ~/Projects/claude-usage-tracker`
4. `Claude Usage.xcodeproj` in Xcode öffnen
5. Dependencies laden lassen (Sparkle via Swift Package Manager)
6. Erstes Build & Run durchführen

---

## Phase 2: Kritische Bugs

### Bug #136 – Leerer Chat alle 5 Minuten
**Symptom:** Alle 5 Minuten öffnet sich ein leerer Browser-Tab oder Chat-Fenster.
**Hypothese:** Ein `Timer.scheduledTimer` mit 5-Minuten-Intervall ruft eine URL auf, die einen Browser öffnet – wahrscheinlich für Session-Refresh gedacht, aber mit unerwünschtem Nebeneffekt.
**Fix:** Timer-Code lokalisieren, URL-Aufruf entfernen oder auf internen API-Call beschränken.

### Bug #139 – Status bleibt auf "gestern" hängen
**Symptom:** Nach Mitternacht zeigt die App noch den Status vom Vortag.
**Hypothese:** Gecachter Timestamp wird beim Tageswechsel nicht invalidiert; Datumsvergleich nutzt evtl. falschen Locale/Timezone-Kontext.
**Fix:** Session-Reset-Logik so anpassen, dass Datum im lokalen Timezone verglichen wird und der Cache beim Tageswechsel geleert wird.

### Bug #145 – Claude CLI Tokens nicht erkannt
**Symptom:** Wenn Claude CLI (claude-code) installiert ist, werden die gespeicherten Credentials nicht von der App gelesen.
**Hypothese:** Neuere Claude CLI Versionen haben den Pfad oder das Format der gespeicherten Credentials geändert (z.B. `~/.config/claude/` statt altem Pfad).
**Fix:** Credential-Pfad und JSON-Parsing an aktuelles Claude CLI Format anpassen.

### Bug #146 – Falsches Profil in Statuszeile
**Symptom:** Bei mehreren Profilen zeigt die Statuszeile (CLI Integration) das falsche aktive Profil an.
**Hypothese:** Index-Problem oder veraltete Binding-Referenz in der Multi-Profil-Statuszeilen-Logik.
**Fix:** Aktives-Profil-State korrekt propagieren; Statuszeile-Output an das tatsächlich aktive Profil binden.

---

## Phase 3: Git-Workflow

- Jeder Bug bekommt einen eigenen Branch: `fix/issue-136-empty-chat`, `fix/issue-139-date-stuck`, etc.
- Ein Commit pro logische Änderung, klare Commit-Messages auf Englisch
- Nach Review: Branch in `main` mergen

---

## Phase 4: Veröffentlichung

1. `CHANGELOG.md` mit Änderungen aktualisieren
2. Version erhöhen (z.B. `2.3.1` als Community-Patch)
3. GitHub Release erstellen (`.dmg` exportieren)
4. `README.md` ergänzen: Hinweis auf Community-Fork-Status

---

## Nicht in Scope

- Feature-Requests (#128, #130, #132, etc.)
- Community-PRs mergen (außer wenn direkt Bug-relevant)
- Komplettes Refactoring

---

## Erfolgskriterien

- [ ] Alle 4 kritischen Bugs reproduziert und gefixt
- [ ] App baut ohne Warnings in Xcode
- [ ] Fork auf GitHub veröffentlicht mit erstem Release
- [ ] Lernziel: Grundverständnis von Swift, SwiftUI und Xcode-Workflow
