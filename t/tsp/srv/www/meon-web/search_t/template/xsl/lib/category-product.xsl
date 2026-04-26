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
<xsl:variable name="current_category_product_ident" select="//w:category-products/w:current-category-product/@ident"/>
<xsl:variable name="current_category_product" select="//w:category-products/w:category-product[@ident=$current_category_product_ident]"/>
<xsl:variable name="no_product_img_src" select="'/static/img/no-product-image.png'"/>

<xsl:template match="w:category-product-view">
    <xsl:call-template name="category-product-view"/>
</xsl:template>

<!-- breadcrumb -->
<xsl:template match="w:category-product-breadcrumb/w:breadcrumb-item">
    <xsl:variable name="ident" select="@ident"/>
    <xsl:variable name="has_next" select="count(following-sibling::node())"/>
    <xsl:apply-templates select='/w:page/w:category-products/w:category-product[@ident=$ident]' mode="breadcrumb-item">
        <xsl:with-param name="has_next">
            <xsl:value-of select="$has_next"/>
        </xsl:with-param>
    </xsl:apply-templates>
</xsl:template>
<xsl:template match="w:category-products/w:category-product" mode="breadcrumb-item">
    <xsl:param name="has_next"/>
    <xsl:variable name="href" select="@href"/>
    <xsl:variable name="title" select="w:title/text()"/>
    <li>
        <xsl:if test="$has_next = 0">
            <xsl:attribute name="class">current</xsl:attribute>
        </xsl:if>
        <a href="{$href}">
            <xsl:value-of select="$title"/>
        </a>
    </li><xsl:text> </xsl:text>
</xsl:template>

<!-- back-to -->
<xsl:template match="w:category-product-breadcrumb/w:breadcrumb-item" mode="back-to">
    <xsl:variable name="ident" select="@ident"/>
    <xsl:variable name="has_next" select="count(following-sibling::node())"/>
    <xsl:if test="$has_next != 0">
    <xsl:apply-templates select='/w:page/w:category-products/w:category-product[@ident=$ident]' mode="category-grid-element-small"/>
    </xsl:if>
</xsl:template>

<!-- category grid element -->
<xsl:template match="w:category-products/w:category-product" mode="category-grid-element">
    <div>
        <xsl:apply-templates select="." mode="category-grid-element-product"/>
    </div>
</xsl:template>
<xsl:template match="w:category-products/w:category-product" mode="category-grid-element-product">
    <xsl:variable name="href" select="@href"/>
    <xsl:variable name="title" select="w:title/text()"/>

    <a class="add_cart_btn" href="{$href}" title="{$title}">
        <h4><xsl:value-of select="$title"/></h4>
    </a>
</xsl:template>

<!-- category or product rendering split -->
<xsl:template name="category-product-view">
    <xsl:variable name="title" select="$current_category_product/w:title/text()"/>

    <div class="breadcrumb">
        <ul>
            <xsl:apply-templates select="/w:page/w:category-products/w:category-product-breadcrumb/w:breadcrumb-item"/>
        </ul>
    </div>

    <xsl:choose>
        <xsl:when test="count($current_category_product/w:subcategory-products)">
            <div class="category-view">
                <h1>Sub-Categories of <xsl:value-of select="$title"/></h1>
                <xsl:apply-templates select='$current_category_product/w:subcategory-products' mode="category-view"/>
            </div>
        </xsl:when>
        <xsl:otherwise>
            <xsl:apply-templates select='$current_category_product' mode="product-view"/>
        </xsl:otherwise>
    </xsl:choose>
</xsl:template>

<xsl:template match="w:category-products/w:category-product/w:subcategory-products/w:category-product" mode="category-view">
    <xsl:variable name="ident" select="@ident"/>
    <xsl:apply-templates select='/w:page/w:category-products/w:category-product[@ident=$ident]' mode="category-grid-element"/>
</xsl:template>

</xsl:stylesheet>
