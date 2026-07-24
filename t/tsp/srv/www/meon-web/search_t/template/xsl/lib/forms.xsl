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
    method="html"
    indent="yes"
    omit-xml-declaration="yes"
    doctype-system="about:legacy-compat"
/>

<!-- for debug -->
<xsl:template match="w:form">
    <xsl:variable name="copy_id" select="@copy-id" />
    <xsl:choose>
        <xsl:when test="string-length($copy_id)">
            <xsl:copy-of select="/w:page/w:forms/xhtml:form[@id=$copy_id]" />
        </xsl:when>
        <xsl:otherwise>
            <xsl:copy-of select="/w:page/w:forms/xhtml:form[1]" />
        </xsl:otherwise>
    </xsl:choose>
</xsl:template>

<xsl:template match="w:input-after">
    <input type="hidden" name="after">
        <xsl:attribute name="value"><xsl:value-of select="/w:page/w:current-uri/text()"/></xsl:attribute>
    </input>
</xsl:template>

<xsl:template match="w:input">
    <xsl:variable name="name" select="@name" />
    <xsl:variable name="src_input" select="/w:page/w:forms//xhtml:input[@name=$name]" />
    <xsl:variable name="has_error" select="/w:page/w:forms//xhtml:input[@name=$name and @class='error']" />
    <input>
        <xsl:for-each select="@*">
            <xsl:variable name="attr_name" select="name()"/>
            <xsl:choose>
                <xsl:when test="$attr_name = 'class' and $has_error">
                    <xsl:attribute name="class"><xsl:value-of select="concat(.,' validation-failed')"/></xsl:attribute>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:attribute name="{$attr_name}"><xsl:value-of select="."/></xsl:attribute>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:for-each>
        <xsl:attribute name="value"><xsl:value-of select="$src_input/@value"/></xsl:attribute>
    </input>
    <xsl:if test="$has_error">
        <div class="validation-advice"><xsl:value-of select="$has_error/../*[@class='help-inline']/text()"/></div>
    </xsl:if>
</xsl:template>

</xsl:stylesheet>
