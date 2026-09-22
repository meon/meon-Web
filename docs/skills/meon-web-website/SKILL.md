---
name: meon-web-website
description: >-
  Use when implementing pages or website features with meon::Web, including
  XML/XSLT frontends, forms, authentication, search, timelines, image galleries,
  and category/product catalogues. Not for unrelated web frameworks or general
  Perl maintenance.
---

# Implementing meon::Web websites

Produce working site files and verify the requested feature through its data,
rendering, and HTTP boundaries. These guides assume access to the target site
and the installed framework source; no other website repository is required.

## Choose the guide

Read only the guides needed for the task:

- For pages, layout, namespaces, CSS, or JavaScript: [Frontend](frontend.md).
- For local form processing and error rendering: [Forms](forms.md).
- For login, protected pages, or roles: [Authentication](authentication.md).
- For indexing, search results, or autocomplete: [Search](search.md).
- For dated entries and archive navigation: [Timeline](timeline.md).
- For image directories and thumbnails: [Image gallery](image-gallery.md).
- For generated categories and product pages:
  [Category/product catalogue](category-product.md).

Read Frontend first when creating a new site or when its rendering path is
unclear. The other guides extend that rendering setup.

## Procedure

1. Locate the target site's instructions and documentation. Identify its host
   mapping, active configuration, page, stylesheet, and editable data sources.
   Resolve symlinks before assuming a directory belongs to this repository.
1. Trace the requested URL: host → site → XML file or handler → access policy →
   includes/forms/runtime data → XSLT → HTML and assets. Start with the relevant
   guide, then verify its connection points against the installed version using
   targeted `rg` searches and source inspection.
1. Implement the smallest complete feature in the site. Preserve existing
   imports, naming, and asset order. A custom `w:` element needs either an XSLT
   template or an implemented backend processor; the namespace alone adds no
   behavior. Keep generators' inputs separate from their outputs.
1. Parse XML/XSLT, transform representative response data, and exercise the
   feature through its actual request path. Include an empty or invalid case
   and the relevant authorization boundary. Synthetic response fixtures verify
   rendering only; they do not prove controller or service integration.
1. Report changed files, observed results, and checks blocked by missing services
   or browser access. Distinguish documented intent from observed implementation
   when they disagree.

## Lookup boundaries

Paths in the guides are relative to the site unless explicitly described as
framework paths. Framework links locate maintained implementation entry points
in this checkout; in an installation, locate the equivalent modules/scripts.

Development can replace `config.ini` with `config_dev.ini`; do not assume a
merged overlay. Authentication of XML pages does not automatically protect
static files, included fragments, or separate APIs. Follow the relevant guide
before publishing sensitive content through those paths.
