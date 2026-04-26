<?xml version="1.0"?>
<xsl:stylesheet
    version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns="http://www.w3.org/1999/xhtml"
    xmlns:xhtml="http://www.w3.org/1999/xhtml"
    xmlns:w="http://web.meon.eu/"
    exclude-result-prefixes="w"
>

<xsl:output
    method="xml"
    indent="yes"
    doctype-system="about:legacy-compat"
/>

<xsl:variable name="newline">
  <xsl:text>&#10;</xsl:text>
</xsl:variable>

<xsl:template match="/w:page">
    <w:opensearch> <xsl:value-of select="$newline"/>
    <xsl:apply-templates select="w:content/w:*"/>
    </w:opensearch> <xsl:value-of select="$newline"/>
</xsl:template>

<xsl:template match="w:category-product-search-items">
    <w:search-category-product> <xsl:value-of select="$newline"/>
    <xsl:apply-templates select="/w:page/w:category-products/w:category-product[@href-canonical]" mode="search-item"/>
    </w:search-category-product> <xsl:value-of select="$newline"/>
</xsl:template>

<xsl:template match="w:category-product" mode="search-item">
    <w:search-item> <xsl:value-of select="$newline"/>
        <w:ident><xsl:value-of select="./@ident"/></w:ident> <xsl:value-of select="$newline"/>
        <w:href><xsl:value-of select="./@href"/></w:href> <xsl:value-of select="$newline"/>
        <xsl:apply-templates
            select="w:title | w:subcategory-products | w:thumb-img-src | w:teaser | w:description"
            mode="copy-for-search"/>
    </w:search-item> <xsl:value-of select="$newline"/>
</xsl:template>

<xsl:template match="w:*" mode="copy-for-search">
    <xsl:copy-of select="."/> <xsl:value-of select="$newline"/>
</xsl:template>

</xsl:stylesheet>
