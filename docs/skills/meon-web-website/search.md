# Search and autocomplete

Build three connections separately: index input, the search service, and the
site's results UI. A search box or a successful fixture transform does not
establish a working search service.

## Supply index input

1. Inspect `perldoc meon::Web::Search`, especially
   `_records_from_content`, `_records_from_category_product`, and
   `_search_xml`. Ordinary pages supply `meta/title` and `content`;
   `meta/robots` containing `noindex` excludes a page. The current indexer
   does not apply the XML-page authentication policy. Exclude private material
   and check API access before indexing it.
1. Provide `include/category-products.xml` and `template/xsl/search.xsl` even
   for a page-only site: the current indexing path invokes the catalogue
   transform first. A page-only site can use an empty `w:category-products`
   root without a filter and a stylesheet returning:

```xml
<w:opensearch xmlns:w="http://web.meon.eu/">
  <w:search-category-product/>
</w:opensearch>
```

1. For a catalogue, use the include/filter setup from
   [Category/product catalogue](category-product.md). Make `search.xsl` emit
   `/w:opensearch/w:search-category-product/w:search-item` records from the
   filtered category data. A representative output record is:

```xml
<w:search-item xmlns:w="http://web.meon.eu/">
  <w:ident>spade</w:ident><w:href>/c/tools/spade</w:href>
  <w:title>Spade</w:title><w:tree-idx>3</w:tree-idx>
  <w:description>A garden tool.</w:description>
  <w:thumb-img-src>/static/spade.jpg</w:thumb-img-src>
</w:search-item>
```

Copy `w:subcategory-products` into category records; emit `w:teaser` when
available. Derive href and tree order from filtered data, not hand-maintained
URLs. This stylesheet produces index input, not browser HTML.

## Connect the service

Configure OpenSearch in the global `etc/meon/web-config.ini` `[search]` section
with `opensearch_nodes`, optional `opensearch_basic_auth`, and optional
`opensearch_cxn_pool` (default `Async::Static`). The nodes and Basic Auth
settings expand `${env:KEY}` placeholders when a client is created. For
example:

```ini
[search]
opensearch_nodes = ${env:OPENSEARCH_TEST_HOST}
opensearch_basic_auth = ${env:OPENSEARCH_TEST_BASIC_AUTH}
```

Use the existing service deployment, or inspect the runner (`script/run_meon-web-search-api`)
and PSGI app (`script/meon-web-search-api.psgi`) to start a test instance. On
public sites, route `/_mws_1/search` and `/_mws_1/autocomplete` to it with the
intended Host: index selection uses the request hostname.

For the configured test hostname, populate the index with:

```sh
meon-web-generate-opensearch --hostname demo.example
```

**This writes to OpenSearch and switches the active index.** Use an isolated
index for tests. `--dry-run` still initializes and populates a working index;
it only suppresses the alias switch. For a read-only preview inspect
`osearch_records` without calling `do_indexing`.

The Search form (`perldoc -T -m meon::Web::Form::Search`) creates a default client
(`perldoc -T -t meon::Web::SearchAPI::Client`). The client lazily parses the site's
`config.ini` `[search] searchapi_url` into its origin and API prefix using URI, then
appends `/search`. For example, `http://127.0.0.1:5001/_mws_1` selects
`http://127.0.0.1:5001/_mws_1/search`. A missing or empty setting uses the
request's base URL plus the default `/_mws_1/search` endpoint. Configured
requests supply the website's hostname in `HTTP_X_FORWARDED_HOST` for index
selection, leaving Host to LWP; enable `USING_FRONTEND_PROXY=1` on the service.
It posts
JSON such as `{"query":"spade","page":1,"size":10}`; the API returns `query`,
`total`, `page`, `size`, and `items`.

## Render the search page

Create `content/search.xml` using the Search metadata and form marker from
[Forms](forms.md), including `<page-size>10</page-size>`. Add a
`<w:search-results/>` marker after the form. Keep the HTML stylesheet for this
page; `template/xsl/search.xsl` is reserved for index input.

Import `template/xsl/lib/search-results.xsl` into the default stylesheet. Bind
`d` to `http://search.cpan.org/perldoc?Data::asXML`. The form serializes
`perldoc meon::Web::SearchAPI::SearchResponse` with Data::asXML, not a flat
list of result nodes. A minimal renderer is:

```xml
<xsl:template match="w:search-results">
  <xsl:variable name="data" select="/w:page/w:search-results/d:HASH"/>
  <xsl:choose>
    <xsl:when test="not($data)"><p>Enter a search term.</p></xsl:when>
    <xsl:otherwise>
      <ul>
        <xsl:for-each select="$data/d:KEY[@name='items']/d:ARRAY/d:HASH">
          <li><a href="{d:KEY[@name='url']/d:VALUE}">
            <xsl:value-of select="d:KEY[@name='title']/d:VALUE"/>
          </a><p><xsl:value-of select="d:KEY[@name='teaser']/d:VALUE"/></p></li>
        </xsl:for-each>
      </ul>
      <xsl:if test="not($data/d:KEY[@name='items']/d:ARRAY/d:HASH)">
        <p>No results.</p>
      </xsl:if>
      <xsl:for-each select="$data/d:KEY[@name='pager']/d:ARRAY/d:HASH">
        <xsl:choose>
          <xsl:when test="d:KEY[@name='href']/d:VALUE">
            <a href="{d:KEY[@name='href']/d:VALUE}">
              <xsl:value-of select="d:KEY[@name='text']/d:VALUE"/>
            </a>
          </xsl:when>
          <xsl:otherwise>
            <span><xsl:value-of select="d:KEY[@name='text']/d:VALUE"/></span>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>
```

For optional autocomplete, use ordinary GET submission to `/search?q=...`.
Post JSON such as `{"query":"spa","limit":10}` to `/_mws_1/autocomplete`;
inspect the API (`perldoc meon::Web::SearchAPI`) for its `items` fields.
Render labels as text, follow the selected item's URL, and cancel or discard
stale responses. Service errors should clear suggestions without disabling
ordinary submission.

For restricted sites, route that autocomplete path to the authenticated
controller (`perldoc meon::Web::Controller::SearchAPI`) to check the user's
session. Configure the site's `[search] searchapi_url` to the service base
URL, such as `http://127.0.0.1:5001/_mws_1`; the controller appends
`/autocomplete`. Enable the service's `USING_FRONTEND_PROXY=1` mode and close
direct public access to it. See the authenticated-autocomplete POD in
`perldoc meon::Web::SearchAPI` for configuration and deployment boundaries.
Authentication grants the site's index; it does not filter results by page
roles. Other search routes require their own access controls. The underscore
prefix alone does not enforce privacy.

## Verify

Check a known result, no results, an empty query, pagination, and unavailable
service behavior. The client raises on failed HTTP or malformed JSON; the
minimal renderer's empty state is not an error handler. Verify the deployed
error page or add the requested application error handling explicitly.

Compare generated records with source content and test the live API using the
same host as the site. Test autocomplete independently, including rapid typing
and failed requests. Search responses require their own access policy;
`restricted_web` does not filter them.
