<?xml version="1.0"?>

<xsl:stylesheet
    version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns="http://www.w3.org/1999/xhtml"
    xmlns:xhtml="http://www.w3.org/1999/xhtml"
    xmlns:w="http://web.meon.eu/"
    xmlns:d="http://search.cpan.org/perldoc?Data::asXML"
    exclude-result-prefixes="w"
>

<xsl:output
    method="html"
    indent="yes"
    omit-xml-declaration="yes"
    doctype-system="about:legacy-compat"
/>

<xsl:variable name="user" select="/w:page/w:user"/>
<xsl:variable name="no_product_img_src" select="'/static/img/no-product-image.png'"/>

<xsl:template match="w:product-view">
    <xsl:variable name="ident" select="@ident"/>
    <xsl:apply-templates select='/w:page/w:category-products/w:category-product[@ident=$ident]' mode="product-view"/>
</xsl:template>

<xsl:template match="w:category-products/w:category-product" mode="product-view">
    <xsl:variable name="ident" select="@ident"/>
    <xsl:variable name="title" select="w:title/text()"/>

    <h3 class="product-title"><xsl:value-of select="$title"/></h3>
    <div class="product-teaser">
        <h5>Teaser</h5>
        <xsl:copy-of select="w:teaser/xhtml:*"/>
    </div>
    <div class="product-description">
        <h5>Description</h5>
        <xsl:copy-of select="w:description/xhtml:*"/>
    </div>
</xsl:template>

</xsl:stylesheet>
