<?xml version="1.0"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:w="http://web.meon.eu/">
  <xsl:output method="xml" omit-xml-declaration="yes"/>
  <xsl:template match="/">
    <html><body><xsl:copy-of select="*"/></body></html>
  </xsl:template>
</xsl:stylesheet>
