# TODO

## Ticket Context

- Auftrag: Skill `docs/skills/meon-web-website/SKILL.md` erstellen.
- Zuerst die drei Beispiel-Repositories durchsuchen und hier relevante
  Konzepte, Quellen und offene Prüfungen sammeln. Diese Recherche ist erledigt;
  Hauptskill und sieben Themenanleitungen sind jetzt angelegt.
- Zielgruppe: Agents, die Websites und Features mit meon::Web implementieren.
- Präzisierung: Der Skill vermittelt, wie man etwas erstellt. Dateiorganisation
  und Rendering-Modell liefern dafür den notwendigen Kontext; eine Beschreibung
  vorhandener Websites erfüllt den Auftrag nicht.
- Die untersuchten Websites dienen ausschließlich als Recherchequellen in
  dieser TODO. Der fertige Skill und seine Begleitdateien nennen oder verlinken
  keine dieser Websites und setzen keinen Zugriff auf deren Repositories voraus.
- Geplante Dateien unter `docs/skills/meon-web-website/`: `SKILL.md`,
  `frontend.md`, `forms.md`, `authentication.md`, `search.md`, `timeline.md`,
  `image-gallery.md` und `category-product.md`.
- Akzeptanz: Der Hauptskill führt von einer Implementierungsaufgabe zur passenden
  Anleitung. Jede Themenanleitung enthält Voraussetzungen, konkrete
  Bearbeitungsorte, Umsetzungsschritte, ein minimales übertragbares Beispiel
  soweit hilfreich und eine Prüfung des fertigen Features.
- Ein Agent muss damit Seiten, Suche, Timeline, Bildergalerie und Produktkatalog
  erstellen können. Begriffe und Dateilisten allein reichen nicht aus.

## Code Context

### Repository-Grenzen und vorhandene Dokumentation

- Alle drei Beispiele sind lokale Symlinks auf eigenständige Repositories:
  [Blog](srv/www/meon-web/blog-kutej-net/),
  [Riedell](srv/www/meon-web/riedell-roller-b2b/),
  [Infinite Human](srv/www/meon-web/infinite-human/).
  Aufgelöste Ziele: `/home/rob/prog/blog-kutej-net`,
  `/home/rob/prog/riedell-roller-b2b`, `/home/rob/prog/infinite-human`.
  Diese Links sind keine Voraussetzung für andere Installationen.
- Einstieg: [Riedell README](srv/www/meon-web/riedell-roller-b2b/README.md).
  Dauerhafte Themendokumentation:
  [Login](srv/www/meon-web/riedell-roller-b2b/docs/login.md),
  [Search](srv/www/meon-web/riedell-roller-b2b/docs/search.md),
  [Produktseiten](srv/www/meon-web/riedell-roller-b2b/docs/product-page.md).
- Auch [archivierte Arbeitsnotizen](srv/www/meon-web/riedell-roller-b2b/docs/todo/)
  durchsucht: Autocomplete, Suchseite, Photos und Dokumentationsumbau.
  Historische Implementierungsdetails nicht als aktuelle Architektur übernehmen.
- Framework-Einstieg: [README](README), [Hauptmodul](lib/meon/Web.pm),
  [Agent-Vorgaben](AGENTS.md). README wird aus POD generiert; für diesen Skill
  ist keine README-Änderung erforderlich.
- Bestehende Änderungen an `etc/meon/web-config.ini` sowie die unversionierte
  `TODO-codereview.md` gehören nicht zu diesem Auftrag.

### Gemeinsame Dateiorganisation

- `content/`: XML-Seiten mit meon-Namespace `http://web.meon.eu/`, Metadaten
  und XHTML-Inhalt. URL-Zuordnung einschließlich `index.xml` im
  [Root-Controller](lib/meon/Web/Controller/Root.pm), `resolve_xml`.
  Dort existiert auch die Auslieferung nicht interpretierter Dateien;
  nicht jede Datei in `content/` ist eine XML-Seite.
- `template/xsl/default.xsl`: Einstieg in die Darstellung; Teiltemplates unter
  `template/xsl/lib/` bauen HTML-Rahmen, Navigation und spezielle Elemente.
  Vergleich: [Blog](srv/www/meon-web/blog-kutej-net/template/xsl/default.xsl),
  [Riedell](srv/www/meon-web/riedell-roller-b2b/template/xsl/default.xsl),
  [Infinite Human](srv/www/meon-web/infinite-human/template/xsl/default.xsl).
- `<meta><template>…</template></meta>` wählt ein alternatives Stylesheet.
  Beispiel: [IH-Startseite](srv/www/meon-web/infinite-human/content/index.xml)
  und [home.xsl](srv/www/meon-web/infinite-human/template/xsl/home.xsl).
  Auflösung: [env.pm](lib/meon/Web/env.pm), `template`.
- `include/` ist optional: wiederverwendbare oder generierte XML-Daten,
  eingebunden mit `w:include`; Implementierung einschließlich `include/auto/`
  in [env.pm](lib/meon/Web/env.pm), `apply_includes`.
  Beispiel: [Katalog-Template](srv/www/meon-web/riedell-roller-b2b/template/xml/category-product.xml)
  und [Katalogdaten](srv/www/meon-web/riedell-roller-b2b/include/category-products.xml).
- `www/static/`: CSS, JavaScript, Bilder, Fonts und Downloads für `/static/`.
  Asset-Einbindung im
  [HTML-Rahmen](srv/www/meon-web/riedell-roller-b2b/template/xsl/lib/html-page.xsl).
- `config.ini`, optional `config_dev.ini`: Site-Einstellungen. Die globale
  Domain-Zuordnung wählt das Site-Verzeichnis. In Development ersetzt eine
  vorhandene `config_dev.ini` die `config.ini`; kein zusammengeführtes Overlay.
  Beleg: [Config.pm](lib/meon/Web/Config.pm), `hostname_to_folder` und Laden
  der Konfiguration; [globale Konfiguration](etc/meon/web-config.ini).
- Außerhalb Development erzeugt `Config.pm` bei Bedarf CSS-/JS-Bundles aus
  den sortierten Dateien der konfigurierten `css-dir`/`js-dir`-Verzeichnisse.
  Einzeldateien und XSLT-Einbindung sind die Bearbeitungsorte, nicht die
  generierten `meon-Web-merged.*`-Dateien. Es ist kein allgemeiner npm-Build.
- `src/`, `script/`, `lib/` und weitere Template-Verzeichnisse sind optionale
  Quellmaterialien, Generatoren oder Site-Erweiterungen, kein Pflichtgerüst.

### Wie Seiten entstehen

- Als Grundlage der Umsetzung erklären: Host → Site → XML-Seite bzw. Handler →
  Laufzeitdaten/Includes/Formverarbeitung → gewähltes XSLT → HTML und Assets.
  Zugriffskontrollen können diese Verarbeitung vorher beenden.
- Quellen: [Root.pm](lib/meon/Web/Controller/Root.pm),
  [env.pm](lib/meon/Web/env.pm), [ResponseXML.pm](lib/meon/Web/ResponseXML.pm)
  und [XSLT-View](lib/meon/Web/View/XSLT.pm).
- `w:`-Elemente unterscheiden: einige verarbeitet das Framework, andere sind
  Platzhalter für Site-XSLT. Ein beliebiger neuer Tag erzeugt keine Backendlogik.
- Blog-Variante: datierte Inhalte, `w:timeline` und Redirect auf das neueste
  Archiv. Quellen: [Startseite](srv/www/meon-web/blog-kutej-net/content/index.xml),
  [Jahresindex](srv/www/meon-web/blog-kutej-net/content/2026/index.xml),
  [Timeline-XSLT](srv/www/meon-web/blog-kutej-net/template/xsl/lib/timeline.xsl).
- Katalog-Variante: `/c/` kann ohne eigene XML-Datei pro URL entstehen.
  [CategoryProduct-Handler](lib/meon/Web/NotFound/CategoryProduct.pm) verbindet
  ein XML-Template mit Katalogdaten; Darstellung bleibt im Site-XSLT.
- Ein [Kataloggenerator](script/meon-web-generate-product-categories) existiert
  im Framework. Die konkrete aktuelle Riedell-Generierung aus
  [src/](srv/www/meon-web/riedell-roller-b2b/src/) ist noch nicht verifiziert;
  keinen ungeprüften Regenerierungsbefehl als Site-Standard dokumentieren.
- IH-Variante: [IH::NotFound](srv/www/meon-web/infinite-human/lib/IH/NotFound.pm)
  kopiert [Kursvorlagen](srv/www/meon-web/infinite-human/template/course/)
  bei passenden Benutzerpfaden in `content/`. Website-Dateien können also auch
  zur Laufzeit entstehen. Eigene Perl-Module und Berichtsvorlagen sind optional.

### Umsetzungsanleitung: Frontend

- `frontend.md`: Eine XML-Seite mit korrekten meon-/XHTML-Namespaces erstellen,
  das XSLT-Template wählen, Teiltemplates importieren und daraus HTML rendern.
- An einem kleinen vollständigen Beispiel zeigen, wie Inhalt, XSLT-Matching,
  HTML-Rahmen, CSS-Klassen und JavaScript-Initialisierung zusammenspielen.
- Erklären, wo CSS und JS angelegt und eingebunden werden; Ladereihenfolge,
  Development-Einzeldateien und generierte Bundles berücksichtigen.
- Zwischen einer rein visuellen XSLT-Komponente und einem Tag unterscheiden,
  der Daten oder Verarbeitung aus dem Backend benötigt.
- Prüfung: XML/XSLT parsen, HTML-Ausgabe und Asset-URLs kontrollieren,
  Browserverhalten und beide Asset-Modi prüfen. Vorhandene Imports und
  Site-Konventionen berücksichtigen, ohne ein bestimmtes Design vorauszusetzen.
- Grundlage sind die oben verlinkten Rendering- und Asset-Implementierungen.

### Umsetzungsanleitung: Forms

- Zusammenhang dokumentieren: XML-Metadaten `form/process` →
  `meon::Web::Form::*` → Werte/Fehler im Response-XML → Site-XSLT/HTML.
- Quellen: [Formverarbeitung](lib/meon/Web/Controller/Root.pm),
  [Form-Rolle](lib/meon/Web/Role/Form.pm),
  [Form-XML](lib/meon/Web/ResponseXML.pm),
  [Search-Form](lib/meon/Web/Form/Search.pm),
  [Seitenbeispiel](srv/www/meon-web/riedell-roller-b2b/content/search.xml),
  [Forms-XSLT](srv/www/meon-web/riedell-roller-b2b/template/xsl/lib/forms.xsl).
- Zeigen, wie ein Agent eine vorhandene Formklasse auswählt, eine Seite damit
  verbindet und Eingaben, Fehler und Erfolg im Frontend abbildet. Erklären,
  wann eine neue Formklasse erforderlich ist und wo sie angeschlossen wird.
- HTTP-Methode, Validierung und Redirects anhand des Ablaufs prüfen.
  Browserformulare können direkt externe APIs ansprechen; nicht jede Form
  durchläuft die lokale Formklasse. Beispiel: Riedells sichtbares Login.

### Umsetzungsanleitung: Authentication

- Site-Formular und Navigation, Framework-Session und Zugriffskontrolle sowie
  externes Auth-System getrennt erklären. Lokale Nutzer und externe
  Authentifizierung nicht zu einer einzigen obligatorischen Architektur machen.
- Quellen: [Login-Dokumentation](srv/www/meon-web/riedell-roller-b2b/docs/login.md),
  [Login-XML](srv/www/meon-web/riedell-roller-b2b/content/login.xml),
  [Members-Controller](lib/meon/Web/Controller/Members.pm),
  [Member.pm](lib/meon/Web/Member.pm), [Root.pm](lib/meon/Web/Controller/Root.pm),
  [Framework-POD](lib/meon/Web.pm).
- Aktuelle Riedell-Konfiguration setzt `restricted_web = 1` in beiden
  Konfigurationsdateien. Aussagen der Site-Dokumentation über anonyme Ansichten
  daher nicht ungeprüft übernehmen.
- `members-only`, `public-access`, Rollen und `/members` konzeptionell
  einordnen. Statische Dateien, Includes und Suchergebnisse haben eigene
  Zugriffsgrenzen; ausgeblendete Navigation ist keine Zugriffskontrolle.
- Portal-Callbacks und systemübergreifendes Logout sind hier nicht vollständig
  belegt. Keine Zugangsdaten oder konkreten Betreiberendpunkte in den Skill.
- Vorgehen zum Einrichten eines Login-Einstiegs und geschützter Seiten geben:
  Auth-Modus bestimmen, Konfiguration setzen, Seite/Form anbinden und erlaubten
  sowie verweigerten Zugriff einschließlich Logout testen.

### Umsetzungsanleitung: Search

- Drei Wege unterscheiden: Index-Eingabedaten, Browser-Autocomplete und
  vollständige Suchseite. Suchdienst und Index sind eigene Komponenten.
- Quellen: [Suchdokumentation](srv/www/meon-web/riedell-roller-b2b/docs/search.md),
  [Suchseite](srv/www/meon-web/riedell-roller-b2b/content/search.xml),
  [Index-XSLT](srv/www/meon-web/riedell-roller-b2b/template/xsl/search.xsl),
  [Ergebnis-XSLT](srv/www/meon-web/riedell-roller-b2b/template/xsl/lib/search-results.xsl),
  [Autocomplete-JS](srv/www/meon-web/riedell-roller-b2b/www/static/js/60_search.js).
- Framework-Anschluss: [Search-Form](lib/meon/Web/Form/Search.pm),
  [SearchAPI-Client](lib/meon/Web/SearchAPI/Client.pm),
  [SearchAPI](lib/meon/Web/SearchAPI.pm), [SearchIndex](lib/meon/Web/SearchIndex.pm).
  Vor Detailaussagen diese Komponenten gezielt lesen; Indexbetrieb und Ranking
  gehören nicht in den Hauptskill.
- `search.md` muss zur Umsetzung führen: Daten für die Indexierung bereitstellen,
  vorhandenen Suchdienst anbinden, Suchformular und Ergebnisseite erstellen,
  Ergebnis-XSLT importieren und bei Bedarf Autocomplete ergänzen.
- Erforderliche Dienstkonfiguration und Datenverträge gegen Framework-Code
  prüfen. Keine betreiberspezifischen URL-Pfade als Standard übernehmen.
- Prüfen: Treffer, leere Ergebnisse, Pagination, Fehler sowie Autocomplete;
  fehlender Suchdienst darf nicht als fertige Suchfunktion gelten.

### Umsetzungsanleitung: Timeline

- `timeline.md`: datierte Einträge und Archiv-/Übersichtsseiten erstellen,
  `w:timeline` verwenden und Einträge mit XSLT darstellen.
- Vor dem Schreiben das erforderliche XML, Datums-/Pfadschema und die
  Auswahl-/Navigationsregeln in [TimelineEntry.pm](lib/meon/Web/TimelineEntry.pm)
  und [Root.pm](lib/meon/Web/Controller/Root.pm) prüfen. Die Blogquellen oben
  dienen als beobachtetes Beispiel, nicht als Voraussetzung für den Leser.
- Die Anleitung muss einen ersten Eintrag und eine funktionierende Übersicht
  ermöglichen. Reihenfolge, Links, Archivnavigation und leere Timeline prüfen.

### Umsetzungsanleitung: Image gallery

- `image-gallery.md`: Bilddateien bereitstellen, Galerie im Seiten-XML
  deklarieren, Bild-/Link-Markup per XSLT erzeugen und optional Browserinteraktion
  ergänzen. Keine bestimmte Lightbox-Bibliothek voraussetzen.
- Zuerst `w:gallery`, Pfadauflösung und erzeugtes Response-XML im
  [Root-Controller](lib/meon/Web/Controller/Root.pm) sowie vorhandene
  Framework-Templates prüfen; die bisherigen Produktphoto-Notizen allein
  belegen noch keine allgemeine Galerieanleitung.
- Prüfung: mehrere Bilder, leere Galerie, korrekte Originalbild-Links,
  Verhalten ohne JavaScript und gegebenenfalls mobile Bedienung.

### Umsetzungsanleitung: Category product

- `category-product.md` erklärt, wie ein Katalog neu erstellt wird:
  Quelldaten und Identifikatoren vorbereiten, Kategorie-/Produktdaten erzeugen,
  Includes und XML-Seitentemplate anlegen, Handler konfigurieren und
  Kategorieübersicht sowie Produktdetails per XSLT darstellen.
- Dazu Generator-Eingabeformat, Pflichtfelder, Ausgabedateien und Aufruf prüfen:
  [Generator](script/meon-web-generate-product-categories),
  [Datenmodell](lib/meon/Web/Data/CategoryProduct.pm),
  [Handler](lib/meon/Web/NotFound/CategoryProduct.pm).
- Ein kleines neutrales Beispiel mit Kategorie und Produkt verwenden.
  Bearbeitbare Quellen von generierten Dateien unterscheiden und beschreiben,
  wie eine Datenänderung bis zur angezeigten Seite gelangt.
- Prüfung: Generierung, Kategorie- und Produkt-URL, Navigation, Bilder sowie
  unbekannter Identifikator. Suchindex-Anbindung bei Bedarf nach `search.md`;
  Preise, Händlerportal und Bestellfunktionen sind keine Katalogvoraussetzung.

## Test Context

- Umsetzung aller fünf beauftragten Schritte am 2026-09-17 autorisiert;
  keine Zwischenfreigaben nötig. Separate Review-Phase bleibt ausgenommen.
- Markdown mit `mdl`, YAML mit `yq`, XML-Beispiele mit `xmllint` und
  relative Links mit einer fokussierten Pfadprüfung validieren.
- Root-README und AGENTS nennen keine Markdown-spezifischen Repositorytests.
- Vor dem Schreiben des Skills gemäß `writing-skills` Implementierungsszenarien mit
  einem Subagent ohne neuen Skill durchführen und Fehlannahmen protokollieren.
  Danach dieselben Szenarien mit Skill prüfen und Lücken korrigieren.
- Szenarien in einem neutralen temporären Website-Gerüst: Seite mit CSS/JS
  erstellen; Formular mit Fehleranzeige anbinden; geschützte Seite einrichten;
  Suche implementieren; Timeline mit Eintrag erstellen; Bildergalerie erstellen;
  kleinen Kategorie-/Produktkatalog erzeugen und darstellen.
- Erfolg an den erzeugten Dateien und ihrer Funktion beurteilen, nicht daran,
  ob ein Agent die Architektur nacherzählen oder Quelldateien finden kann.
- Hauptskill: YAML-Frontmatter mit `name: meon-web-website` und einer mit
  `Use when...` beginnenden Triggerbeschreibung; kompakt, möglichst unter
  500 Wörtern. Markdown, Frontmatter und relative Referenzlinks validieren.
- Endgültigen Skill und alle Begleitdateien auf Website-Namen, Beispielrepo-
  Links und lokale Betreiberpfade prüfen: keine übernehmen. Framework-Pfade
  dürfen als zusätzliche Orientierung dienen, ersetzen aber keine Anleitung.

## Plan

- [x] Drei Repositories und Riedell-Dokumentation durchsuchen; Konzepte,
  Quellen, Unterschiede und offene Prüfungen in neuer TODO sammeln.
- [x] TODO mit Markdown-Linter und Prüfung der Quellenlinks validieren.
- [x] Ziel auf ausführbare Implementierungsanleitungen präzisieren; Frontend,
  Timeline, Bildergalerie und Katalog ergänzen; Website-Referenzen ausschließen.
- [x] Implementierungsszenarien ohne Skill ausführen; Lücken festhalten.
- [x] Hauptskill und sieben Themenanleitungen aus geprüften Quellen schreiben;
  oben genannte offene Detailprüfungen bei Bedarf abschließen.
- [x] Szenarien mit Skill wiederholen, Lücken korrigieren und erneut prüfen.
- [x] Frontmatter, Markdown, Links und Umfang validieren; Ergebnis festhalten.
- [x] Prüfen, ob ein knapper Eintrag in [Changes](Changes) zur neuen
  Entwicklerdokumentation der bisherigen Konvention entspricht.
- [ ] Separate Review-Phase nach Fertigstellung und Validierung.

## Umsetzungsnachweis vom 2026-09-17

### Baseline ohne neuen Skill

- Frischer Subagent mit Framework und README, ohne diese TODO, neue Anleitungen
  oder externe Website-Repositories. Auftrag: sieben neutrale Features als
  Dateien erstellen und mit verfügbaren Komponenten prüfen.
- Artefakte: `/tmp/meon-baseline/site`, Workbook `catalogue.xls`,
  `check.pl`, `check.log` und gerenderte HTML-Dateien im selben Testverzeichnis.
- Beobachtet: elf XML-/XSL-Dateien geparst; ungültige Formulareingabe abgewiesen;
  Timeline-Titel und Datum gelesen; Suchantwort mit Data::asXML gerendert;
  Galerie mit simulierten Controllerdaten und erzeugtem Thumbnail dargestellt.
  Kategorie-, Produkt- und Home-XML liegen als Generatorausgabe vor.
- Konkrete Lücke: Der Form-/Suchtest baut eine `rxml`-Wurzel um die Seite.
  `Root::resolve_xml` verwendet tatsächlich die Seite selbst als Response-DOM.
  Der Baseline-Selektor `/*/w:forms/*` toleriert beides, der Test belegt den
  echten Requestpfad trotzdem nicht. Die Anleitung zeigt den echten Seitenpfad.
- Weitere beobachtete Lücken: Timeline-Darstellung ohne anklickbaren Detailtitel;
  keine Pagination im Suchrenderer; Katalog-Summary ohne Filtermarker.
  Anleitungen enthalten diese Anschlüsse ausdrücklich.
- Vom Agent ermittelte Voraussetzungen: explizites `page-size`, Perl-Suchpfad
  für eigene Formklassen, Galerie relativ zur XML-Datei, vorhandene
  Katalog-Summary und Masterkategorie `home`.
- Der Agent endete am Nutzungslimit vor seinem Abschlussbericht. Aussagen oben
  stammen aus erhaltenen Dateien, Prüflog und Zwischenmeldung; vollständige
  HTTP-, Browser- und Dienstintegration wurde damit nicht nachgewiesen.

### Quellenprüfung und Umsetzung

- Acht Dateien unter `docs/skills/meon-web-website/` erstellt. Hauptskill routet
  bedingt zu den sieben Themen. Keine Beispielwebsite, lokalen Betreiberpfade
  oder Abhängigkeiten auf andere Skills in den neuen Anleitungen.
- Offene Details gegen Framework geprüft: Gallery-Pfade und Thumbnail-Caching;
  Timeline-Datumsformat, erste Timeline pro Seite und Archive; Form-Response-DOM;
  Katalog-XLS-Eingabe, Summary-Initialisierung, Filter und URL-Handler;
  Search-Indexer, Client, API, Data::asXML und Pagination.
- Katalogquelle der recherchierten Website nicht weiter untersucht: Die neue
  Anleitung verwendet den geprüften Framework-Generator und behauptet keinen
  website-spezifischen Regenerierungsbefehl.
- `Changes` enthält kurze englische Funktionsstichpunkte. Ein ebenso knapper
  Dokumentationseintrag passt dazu; unter `Unreleased` ergänzt, ohne eine
  bestehende Release-Datierung zu ändern.

### Lokale Validierung

- `mdl docs/skills/meon-web-website`: bestanden, nach Korrektur der Einrückung
  einer Markdown-Tabelle.
- `quick_validate.py docs/skills/meon-web-website`: bestanden.
- Frontmatter mit `yq` geparst; Name, Triggerbeschreibung, relative Links,
  Website-Ausschlüsse und Hauptskill unter 500 Wörtern geprüft.
- 16 XML-Blöcke mit `xmllint` geparst; XSLT-Fragmente dabei mit den dokumentierten
  Namespace-Deklarationen umschlossen. Alle sechs Stylesheets kompilieren.
- `/tmp/check-meon-guides.pl`: 21 erfolgreiche Prüfungen für Frontend, Form-DOM
  mit Fehleranzeige, Timeline-Modell, Katalogmodell/-filter (inklusive 404),
  Ergebnisse/Leerzustand und Suchpagination. XSLT-Fragmente mit Frontend-Vorlage
  kombiniert. Ein anfänglich zu enger HTML-Regulärausdruck und unvollständiger
  Testaufbau wurden korrigiert; kein Framework-Code geändert.
- Formularbeispiel als Perl-Modul geladen: ungültige E-Mail mit sichtbarem
  Fehler und gültige E-Mail geprüft. Redirect benötigt einen Request-Kontext.
- Echter XLS-Generatorlauf in `/tmp/meon-guide-generator`: drei Datensätze,
  Kategoriezuordnung und Filtermarker-Erhalt geprüft. Geschützte Metadaten
  außerdem gegen `env::page_requires_login` geprüft.
- Testskripte und Fixtures sind temporäre Prüfarbeitsmittel, keine zusätzlichen
  produktiven Dateien. Live-OpenSearch, Browserbedienung, externe Anmeldung und
  vollständige HTTP-/Sessionintegration sind nicht durch diese Checks abgedeckt.

### Unabhängiger Durchlauf mit Skill

- Neuer Agent ohne Baseline-Kontext, mit Hauptskill und relevanten Anleitungen:
  alle sieben Feature-Fixtures unter `/tmp/meon-with-skill` erstellt.
  Bericht `/tmp/meon-with-skill-results.md`, Prüflog `check.log`.
- 24/24 Assertions bestanden; 21 XML-/XSL-Dateien mit `xmllint` geparst.
  Geprüft: tatsächliche Formularvalidierung/ResponseXML, Kataloggenerierung
  über das Modell, Filter inklusive 404 und 302, SearchAPI-Client mit
  simuliertem HTTP-Transport und echtem Serializer, Fehlerantworten sowie
  `members-only`-Policy. Renderingfixtures für Timeline und Galerie bestanden.
- Der Agent erkannte eine unabhängige Python-CSV-Aufgabe als außerhalb des
  Skill-Triggers. Dies ist ein einzelner Klassifikationsfall, kein Benchmark.
- Nachgebessert: `forms.md` erklärt für direkte Framework-Checks das notwendige
  `as_xml` nach `add_xhtml_form`, damit gepufferte Elemente vor dem Transform
  im DOM stehen. Frischer Agent hat diesen Fall mit gültiger/ungültiger
  Eingabe erneut geprüft.
- Keine Behauptung vollständiger End-to-End-Abdeckung: Die Agent-Fixtures
  ersetzen keine laufenden Services, Browser- oder Sessiontests. Der zusätzliche
  lokale XLS-Test deckt den im Agent-Durchlauf nicht ausgeführten Importer ab.

- Abschlussprüfung: alle TODO-Quellenlinks, alle Skill-Links, Frontmatter,
  Markdown und `git diff --check` bestanden. `Changes` mit fokussierter
  Struktur-/Whitespace-Prüfung validiert; INI-Beispiel erfolgreich geparst.
- Zusätzliche JavaScript-Syntaxprüfung konnte mangels `node` nicht ausgeführt
  werden; Browserausführung bleibt ungetestet. Keine Abhängigkeiten installiert.

- Frischer Form-Nachtest nach Ergänzung: 10/10 Assertions bestanden
  (`perl /tmp/meon-form-recheck/check.pl`). Echte FormHandler-Validierung,
  ResponseXML und LibXSLT; ungültige Eingabe samt sichtbarer Fehlermeldung
  erhalten, gültige Eingabe ohne Fehler, Redirect nur bei gültiger Eingabe.
  Redirect-Callback mit lokalem Kontext geprüft, kein HTTP-Request.
- Alle fünf beauftragten Umsetzungsschritte abgeschlossen. Separate
  Review-Phase bleibt offen; keine Commits, keine Änderungen am Framework-Code.
