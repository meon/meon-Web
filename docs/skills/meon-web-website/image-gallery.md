# Image galleries

Start with a page and stylesheet from [Frontend](frontend.md). The built-in
gallery scans a directory relative to the source XML page and writes thumbnails
there. The application needs read access to originals and write access to the
thumbnail directory.

## Build the gallery

1. Create `content/photos/index.xml` and place two image files in
   `content/photos/images/`. Use ordinary image filenames initially. Keep
   non-image files out: the scanner skips directories and `.xml` files but does
   not otherwise filter by image format.
1. Put this marker inside the page's XHTML content wrapper:

```xml
<w:gallery xmlns:w="http://web.meon.eu/" href="images"
           thumb-width="240" thumb-height="180"/>
```

1. Add this XSLT template, using the stylesheet namespace declarations from
   Frontend:

```xml
<xsl:template match="w:gallery">
  <div class="gallery">
    <xsl:for-each select="w:img">
      <a href="{@src}">
        <img src="{@src-thumb}" alt="{@alt}" title="{@title}"/>
      </a>
    </xsl:for-each>
    <xsl:if test="not(w:img)"><p>No pictures yet.</p></xsl:if>
  </div>
</xsl:template>
```

1. Request `/photos/`. The controller appends `w:img` elements with `src`,
   `src-thumb`, `title`, and `alt`; it creates missing thumbnails under
   `images/thumb/`. The originals remain normal links without JavaScript.
1. Add CSS to the site's asset sources. Add optional lightbox behavior only
   after ordinary links work; preserve keyboard access and a no-JavaScript path.

A missing image directory raises an error; an existing empty directory yields
an empty gallery. Existing thumbnails are reused without a freshness check.
After changing an original or thumbnail dimensions, remove only the affected
generated thumbnails in the target site and request the page again.

## Verify

Parse XML/XSLT, request the gallery, and check both original and thumbnail URLs,
image dimensions, multiple-image ordering, and the empty state. Test without
JavaScript and, if enhanced, keyboard and mobile operation. Include a filename
with spaces when the site's uploads allow it; URL encoding and filesystem
handling must work together.

The [gallery loop](../../../lib/meon/Web/Controller/Root.pm) in `resolve_xml`
is the source for path and output behavior. Its containment check does not
turn direct image URLs into authenticated downloads. Apply separate access
control when originals must remain private, as described in
[Authentication](authentication.md).
