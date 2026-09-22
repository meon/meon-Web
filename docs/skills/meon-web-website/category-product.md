# Category and product catalogues

Start with a configured site and the renderer from [Frontend](frontend.md).
The catalogue consists of editable source data, generated include XML, a dynamic
page template, and XSLT. It does not require pricing or an ordering portal.

## Generate neutral catalogue data

1. Prepare a legacy `.xls` workbook accepted by `Spreadsheet::ParseExcel`.
   Use columns `ordering-ident`, `ident`, and `title`. A category row has an
   empty `ordering-ident`; following product rows belong to that category:

| ordering-ident | ident | title |
| --- | --- | --- |
| | tools | Tools |
| T-1 | spade | Spade |

   Put a category before its products. Use unique, simple identifiers and
   validate the required columns yourself: the generator warns about missing
   columns but does not reliably stop on that warning.
1. Create `include/category-products.xml` before the first generation:

```xml
<w:category-products xmlns:w="http://web.meon.eu/">
  <w:apply-filter ident="CategoryProduct"/>
</w:category-products>
```

1. In the framework environment, run the installed generator against the
   intended site directory name, not its hostname or an arbitrary absolute path:

```sh
meon-web-generate-product-categories \
  --hostname-dir demo-site --master-category home catalogue.xls
```

The [generator](../../../script/meon-web-generate-product-categories) resolves
that name under the installation's `srv/www/meon-web/`. Substitute the real
site directory and use a disposable site for experimentation. It updates
`include/category-product/IDENT.xml` and `include/category-products.xml`.
The master category must be `home` for the built-in filter. The
[data model](../../../lib/meon/Web/Data/CategoryProduct.pm) loads the existing
summary during each store; it does not initialize the summary for you.

The spreadsheet importer handles titles, ordering identifiers, and category
membership. It does not import every possible spreadsheet column. Extend the
site's source-to-XML pipeline for descriptions and images, using the model's
`set_element` and `store` methods where appropriate. Products initially receive
a `TODO` description when none exists; replace it before publishing. Keep
editable sources and regeneration commands together in site documentation.

## Connect URLs and rendering

Set the active site configuration:

```ini
[main]
not-found-handler = meon::Web::NotFound::CategoryProduct
```

Create `template/xml/category-product.xml`:

```xml
<page xmlns="http://web.meon.eu/" xmlns:w="http://web.meon.eu/">
  <meta><title>Catalogue</title></meta>
  <content><div xmlns="http://www.w3.org/1999/xhtml">
    <w:catalogue-view/>
  </div></content>
  <w:include path="category-products.xml">
    <w:current-category-product/>
    <w:category-product-breadcrumb/>
  </w:include>
</page>
```

The handler fills the current identifier and breadcrumb from `/c/...`. The
`CategoryProduct` include filter selects context, resolves links, and rejects
unknown identifiers. Both markers inside the include and the filter marker in
the summary are needed. Do not expect the handler alone to validate products.

Add the following template to the site's XSLT. It shows a category's children
or a product's details, using the Frontend namespace declarations:

```xml
<xsl:template match="w:catalogue-view">
  <xsl:variable name="data" select="/w:page/w:category-products"/>
  <xsl:variable name="id" select="$data/w:current-category-product/@ident"/>
  <xsl:variable name="item" select="$data/w:category-product[@ident=$id]"/>
  <nav>
    <xsl:for-each select="$data/w:category-product-breadcrumb/w:breadcrumb-item">
      <xsl:variable name="ancestor" select="@ident"/>
      <xsl:for-each select="$data/w:category-product[@ident=$ancestor]">
        <a href="{@href}"><xsl:value-of select="w:title"/></a>
      </xsl:for-each>
    </xsl:for-each>
  </nav>
  <h1><xsl:value-of select="$item/w:title"/></h1>
  <p><xsl:value-of select="$item/w:description"/></p>
  <xsl:if test="$item/w:thumb-img-src">
    <img src="{$item/w:thumb-img-src}" alt="{$item/w:title}"/>
  </xsl:if>
  <ul>
    <xsl:for-each select="$item/w:subcategory-products/w:category-product">
      <xsl:variable name="child" select="@ident"/>
      <xsl:for-each select="$data/w:category-product[@ident=$child]">
        <li><a href="{@href}"><xsl:value-of select="w:title"/></a></li>
      </xsl:for-each>
    </xsl:for-each>
  </ul>
</xsl:template>
```

Use `/c/tools` and `/c/tools/spade` for the example. For a catalogue landing
page at `/`, reuse the template as `content/index.xml`, setting the include's
current `ident="home"` and breadcrumb `href="home"`. The generated home needs
a title if the landing renderer should display one.

## Verify

Parse generated XML, exercise category and product requests, and inspect the
post-filter response before transforming it. Test child links, breadcrumb,
image URLs, an unknown identifier, and a known identifier under a wrong parent
(the filter may redirect). Change a source title, regenerate, and verify the
rendered change. Repeated generation does not imply deleted source rows are
removed; inspect and reconcile obsolete records explicitly.

Use [Search](search.md) when indexing is requested. Inspect
[the handler](../../../lib/meon/Web/NotFound/CategoryProduct.pm) and
[the filter](../../../lib/meon/Web/Filter/CategoryProduct.pm) if URL behavior
in the installed version differs.
