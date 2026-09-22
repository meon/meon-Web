# Login and protected pages

Identify the deployed authentication mode before editing login UI. Local XML
users, framework-driven external authentication, and browser forms posting to
an external portal have different integration points. A rendered login form
alone does not establish a session.

## Set up a local entry point

1. Inspect the site's active configuration and
   [Root login/logout actions](../../../lib/meon/Web/Controller/Root.pm).
   For local users, ensure the existing provisioning flow creates an active
   user under `content/members/profile/`; inspect
   [Member](../../../lib/meon/Web/Member.pm) and
   [registration](../../../lib/meon/Web/Form/MemberRegistration.pm) before
   creating accounts. Do not invent a password-storage XML format.
1. Create `content/login.xml` with ordinary page metadata and this content:

```xml
<content xmlns="http://web.meon.eu/" xmlns:w="http://web.meon.eu/">
  <div xmlns="http://www.w3.org/1999/xhtml">
    <h1>Log in</h1><w:form copy-id="form_login"/>
  </div>
</content>
```

Use the form-copy template from [Forms](forms.md). The `/login` controller
constructs `Form::Login` itself; do not add `meta/form/process=Login`.
Link navigation to `/login` and `/logout`. Confirm the emitted form's action
and POST behavior on direct login and on a protected-page request.

1. Create `content/private.xml`. Protect it with the following metadata; add
   the `access` element only if the feature needs the named role:

```xml
<meta xmlns="http://web.meon.eu/">
  <title>Private workspace</title>
  <members-only/>
  <access><role>editor</role></access>
</meta>
```

Each listed role is required for authenticated users. Roles alone do not force
anonymous users to log in; combine them with `members-only` or site-wide
restriction. The [Members controller](../../../lib/meon/Web/Controller/Members.pm)
also gates its `/members` routes.

## Restrict a whole site

Set `[main] restricted_web = 1` in the effective site configuration. Add
`<public-access/>` directly to metadata for public landing, reset, activation,
or external-registration pages. `members-only` takes precedence; both markers
are presence tests. Use `0` to disable the setting, not the strings `false` or
`off`. Development configuration replaces the normal configuration.

Root login/logout and error pages are exceptions; inspect
[env page policy](../../../lib/meon/Web/env.pm), `is_public_endpoint` and
`page_requires_login`, for symlink resolution. Access checks precede includes,
forms, and page redirects.

For external authentication, verify `[auth]` settings against the deployed
login action, and inspect the external service's callback/session contract.
A browser form posting elsewhere bypasses the local credential-processing
path. Local `/logout` deletes the meon::Web session; it does not establish that
an external system logged out. Test both systems when both participate.

## Verify the boundary

Test anonymous access, valid credentials, invalid credentials, an authenticated
user missing a required role, and logout followed by a fresh protected request.
Check login/reset entry points without an existing cookie. Production session
cookies require HTTPS; the framework POD describes session configuration.

Test protected content through its direct URL and listings. Static assets,
non-XML downloads, `[raw_xml]` exceptions, includes in public pages, and separate
search/API responses are outside the XML-page restriction. Keep confidential
content out of those public paths or add the appropriate server/service access
control. Hidden navigation is only presentation.
