# Timeline entries and archives

Use the page and XHTML-copy templates from [Frontend](frontend.md). A folder
timeline lists entries beside its XML page, not all descendants recursively.

## Create an entry and overview

Create `content/news/2026/09/first-entry.xml`:

```xml
<page xmlns="http://web.meon.eu/" xmlns:w="http://web.meon.eu/">
  <meta><title>First entry</title></meta>
  <content><div xmlns="http://www.w3.org/1999/xhtml">
    <w:timeline-entry category="news">
      <w:created>2026-09-17T12:00:00</w:created>
      <w:title>First entry</w:title>
      <w:intro>A short introduction.</w:intro>
      <w:text><p>The full entry.</p></w:text>
    </w:timeline-entry>
  </div></content>
</page>
```

`w:title` and `w:created` belong to the entry, independently of the page title.
The [entry model](../../../lib/meon/Web/TimelineEntry.pm) parses the timestamp
as UTC using `%FT%T`. Its file-creation path uses `YYYY/MM/filename.xml`.

Create `content/news/2026/09/index.xml` as a page with
`<w:timeline/>` inside its XHTML content wrapper. Add these templates to a
stylesheet imported by the site (namespaces as in Frontend):

```xml
<xsl:template match="w:timeline">
  <section>
    <xsl:apply-templates select="w:timeline-entry"/>
    <xsl:for-each select="w:older | w:newer">
      <a href="{@href}"><xsl:value-of select="local-name()"/></a>
    </xsl:for-each>
    <xsl:if test="not(w:timeline-entry)"><p>No entries yet.</p></xsl:if>
  </section>
</xsl:template>
<xsl:template match="w:timeline-entry">
  <article>
    <h2><xsl:choose>
      <xsl:when test="@href">
        <a href="{@href}"><xsl:value-of select="w:title"/></a>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="w:title"/></xsl:otherwise>
    </xsl:choose></h2>
    <time><xsl:value-of select="w:created"/></time>
    <xsl:choose>
      <xsl:when test="@href"><p><xsl:value-of select="w:intro"/></p></xsl:when>
      <xsl:otherwise><xsl:apply-templates select="w:text/node()"/></xsl:otherwise>
    </xsl:choose>
  </article>
</xsl:template>
```

The controller appends entry elements with `href`, sorted newest first. For an
explicit list use a non-folder class, for example
`<w:timeline class="selected"><w:timeline-entry
href="/news/2026/09/first-entry"/></w:timeline>`; references omit `.xml`.
Only the first timeline on a page is processed.

For year/root indexes, adapt the framework
[redirect index](../../../share/meon-web/template/xml/timeline-index.xml)
and [month listing](../../../share/meon-web/template/xml/timeline-list-index.xml).
The redirect uses `{$TIMELINE_NEWEST}/`; verify its resolved destination.
Older/newer navigation walks numeric archive directories and their indexes.
Inspect `_older_entries`, `_newer_entries`, and `_append_timeline_navigation` in
[Root](../../../lib/meon/Web/Controller/Root.pm) when changing archive structure.

## Verify

Parse and render the entry, then request the month overview through the
controller. Add a second entry with a different date and another month; check
order, detail links, archive navigation, and an empty month. Test a protected
entry anonymously and while logged in. A manually appended entry tests XSLT
only, not discovery, ordering, or access filtering.
