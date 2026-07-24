<?xml version="1.0"?>

<xsl:stylesheet
    version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns="http://www.w3.org/1999/xhtml"
    xmlns:xhtml="http://www.w3.org/1999/xhtml"
    xmlns:w="http://web.meon.eu/"
    xmlns:d="http://search.cpan.org/perldoc?Data::asXML"
    exclude-result-prefixes="w d"
>

<xsl:output
    method="html"
    indent="yes"
    omit-xml-declaration="yes"
    doctype-system="about:legacy-compat"
/>

<xsl:template match="w:search-results">
    <div class="search-results">
        <xsl:variable name="result_data" select="/w:page/w:search-results/d:HASH"/>
        <xsl:choose>
            <xsl:when test="$result_data">
                <xsl:variable name="query" select="$result_data/d:KEY[@name='query']/d:VALUE/text()"/>
                <xsl:variable name="total" select="$result_data/d:KEY[@name='total']/d:VALUE/text()"/>
                <h2>Search Results</h2>
                <p>
                    Query: <b><xsl:value-of select="$query"/></b>
                    (<xsl:value-of select="$total"/> hits)
                </p>
                <ul>
                    <xsl:for-each select="$result_data/d:KEY[@name='items']/d:ARRAY/d:HASH">
                        <xsl:variable name="url" select="d:KEY[@name='url']/d:VALUE/text()"/>
                        <xsl:variable name="title" select="d:KEY[@name='title']/d:VALUE/text()"/>
                        <li>
                            <a href="{$url}"><xsl:value-of select="$title"/></a>
                        </li>
                    </xsl:for-each>
                </ul>
                <xsl:if test="not($result_data/d:KEY[@name='items']/d:ARRAY/d:HASH)">
                    <p>No results.</p>
                </xsl:if>
            </xsl:when>
            <xsl:otherwise>
                <p>Use the search form to submit a query.</p>
            </xsl:otherwise>
        </xsl:choose>
    </div>
</xsl:template>

</xsl:stylesheet>
