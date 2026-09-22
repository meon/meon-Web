# Local forms

Start with a working page and stylesheet from [Frontend](frontend.md). Decide
whether the browser submits to meon::Web or to an external API. This guide
covers the local path; an external form needs its own endpoint contract.

## Connect processing and rendering

1. Inspect [form classes](../../../lib/meon/Web/Form) for the required behavior.
   Read the selected class's fields, `http_method`, `submitted`, and every
   `get_config_text` call. Supply those metadata elements: missing configuration
   raises an exception, even when a caller appears to provide a default.
1. Set the class suffix in page metadata. For the existing Search class:

```xml
<page xmlns="http://web.meon.eu/" xmlns:w="http://web.meon.eu/">
  <meta>
    <title>Search</title>
    <form><process>Search</process><page-size>10</page-size></form>
  </meta>
  <content><div xmlns="http://www.w3.org/1999/xhtml">
    <w:form copy-id="form-search"/>
  </div></content>
</page>
```

1. Implement the marker in the site's stylesheet, with `w`, `xsl`, and XHTML
   prefix `x` bound as in Frontend:

```xml
<xsl:template match="w:form[@copy-id]">
  <xsl:variable name="id" select="@copy-id"/>
  <xsl:copy-of select="/w:page/w:forms/x:form[@id=$id]"/>
</xsl:template>
```

`Root::resolve_xml` sets the ResponseXML document to the page before adding
forms. Generated XHTML forms therefore live under `/w:page/w:forms`, including
field values and validation errors. The standalone ResponseXML default root
`rxml` is not the normal page response. Copying the rendered form preserves
its errors; custom markup must map field values and errors deliberately.
Search also needs the service and result renderer in [Search](search.md).

## Add a form class when needed

Create `lib/meon/Web/Form/Enquiry.pm` in a module directory available to the
application's Perl `@INC`; a site-local `lib/` is not automatically loaded.
For a minimal validation and redirect example:

```perl
package meon::Web::Form::Enquiry;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
with 'meon::Web::Role::Form';
has '+name' => (default => 'form-enquiry');
has '+http_method' => (default => 'POST');
has_field 'email' => (type => 'Email', required => 1);
has_field 'submit' => (type => 'Submit', value => 'Continue');
sub submitted {
    my ($self) = @_;
    $self->redirect($self->get_config_text('redirect'));
}
no HTML::FormHandler::Moose;
1;
```

Set `<process>Enquiry</process><redirect>/thanks</redirect>` inside `meta/form`,
use `copy-id="form-enquiry"`, and create `content/thanks.xml`. This example
validates and redirects; add the requested persistence or delivery operation
inside `submitted` to implement a real enquiry workflow.

The controller takes query parameters for GET forms and body parameters for
other forms. It calls `submitted` only when validation succeeds and the request
method matches. The [form role](../../../lib/meon/Web/Role/Form.pm) supplies
configuration and redirect helpers; do not treat a page-level redirect as a
successful-submission handler because it runs before form processing.

## Verify

Compile the class with the intended `PERL5LIB`. Request the page before any
submission, submit an invalid email, and check visible errors and retained
values in the generated HTML. Submit a valid email and verify the redirect and
its target. Check that invalid or wrong-method requests do not perform the
operation. For custom markup, inspect actual response XML using
[ResponseXML](../../../lib/meon/Web/ResponseXML.pm) and the controller flow;
a hand-built `rxml` fixture can conceal a wrong XPath. In a direct framework
check, initialize ResponseXML with the page DOM, call `add_xhtml_form`, then
transform `as_xml`; the latter flushes queued form elements into the document.
