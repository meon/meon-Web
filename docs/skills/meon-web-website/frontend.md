# Pages, layout, and assets

Use a configured site with a working meon::Web runtime. Verify its host mapping
in the global `[domains]` section: each key is a site directory and its value
contains hostnames. Locate that directory through the installed
[Config module](../../../lib/meon/Web/Config.pm), rather than assuming a fixed
system prefix. Development loads `config_dev.ini` instead of `config.ini`
when that file exists.

## Build a first page

1. Create `content/hello.xml` for `/hello`; a directory URL uses `index.xml`.
1. Add content in the XHTML namespace. Use the meon namespace for page metadata
   and feature elements. The following is a complete page:

```xml
<page xmlns="http://web.meon.eu/"
      xmlns:w="http://web.meon.eu/">
  <meta><title>Hello</title></meta>
  <content>
    <main xmlns="http://www.w3.org/1999/xhtml">
      <h1 class="greeting">Hello</h1>
      <button id="greet" type="button">Greet</button>
      <p id="reply" aria-live="polite"/>
    </main>
  </content>
</page>
```

1. Create `template/xsl/default.xsl` for a new site, or extend the existing
   stylesheet through `template/xsl/lib/` imports. Put `xsl:import` before other
   top-level declarations. A minimal standalone stylesheet is:

```xml
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:w="http://web.meon.eu/"
    xmlns:x="http://www.w3.org/1999/xhtml"
    exclude-result-prefixes="w x">
  <xsl:output method="html"/>
  <xsl:template match="/w:page">
    <html><head>
      <title><xsl:value-of select="w:meta/w:title"/></title>
      <link rel="stylesheet" href="/static/css/10_site.css"/>
      <script src="/static/js/10_site.js" defer="defer">
        <xsl:text> </xsl:text>
      </script>
    </head><body>
      <xsl:apply-templates select="w:content/node()"/>
    </body></html>
  </xsl:template>
  <xsl:template match="x:*">
    <xsl:element name="{local-name()}">
      <xsl:copy-of select="@*"/>
      <xsl:apply-templates/>
    </xsl:element>
  </xsl:template>
</xsl:stylesheet>
```

1. Add `www/static/css/10_site.css` containing
   `.greeting { color: #245; }`. Add `www/static/js/10_site.js`:

```javascript
const button = document.getElementById('greet');
if (button) {
  button.addEventListener('click', () => {
    document.getElementById('reply').textContent = 'Welcome';
  });
}
```

The `/static/` controller serves `www/static/`. A metadata element such as
`<template>landing</template>` selects `template/xsl/landing.xsl`.
For reusable XML, create `include/navigation.xml` and insert
`<w:include path="navigation.xml"/>` in the page. Includes replace their marker
with the included document's root; account for that root in the XSLT.
`include/auto/`, when present, is included automatically.

## Extend presentation or processing

For a visual component, declare a neutral marker such as `<w:notice/>` and add
an XSLT template matching `w:notice`. If it needs submitted values or generated
data, use the corresponding form or feature guide. XSLT cannot make an unknown
marker execute Perl code.

Keep asset source files in deterministic dependency order. Sites using
`[main]` keys `css-dir` and `js-dir` generate `meon-Web-merged.css` and
`meon-Web-merged.js` outside Development when configuration loads. Point the
production XSLT at `/static/meon-Web-merged.css` and
`/static/meon-Web-merged.js`, retaining individual assets in Development.
Use the site's existing environment branch and verify `w:run-env` in response
XML. Do not load both modes or edit generated bundles. The standalone example
above deliberately uses individual files and needs no bundling configuration.

## Verify

Run from the site directory:

```sh
xmllint --noout content/hello.xml template/xsl/default.xsl
xsltproc template/xsl/default.xsl content/hello.xml > /tmp/meon-hello.html
```

Check the resulting title, content, and asset URLs, then request `/hello` with
the configured host. Test the button in a browser, console errors, keyboard
operation, and both asset modes if configured. A raw page transform cannot test
includes, forms, or runtime data. In a debug runtime, `?debug_xml=1` exposes
response XML for checking actual XPath locations; keep it out of public output.

For resolution and processing order inspect
[Root](../../../lib/meon/Web/Controller/Root.pm), `resolve_xml`; for includes and
stylesheet selection inspect [env](../../../lib/meon/Web/env.pm),
`apply_includes` and `template`.
