# TODO

## Ticket Context

Add an opt-in website setting, `[main] restricted_web=1` in the site's
`config.ini`, that makes pages require authentication by default. A page can
allow anonymous access with `/w:page/w:meta/w:public-access`. Login and logout
must always remain publicly accessible.

Acceptance criteria:

- Missing `restricted_web` or `restricted_web=0` preserves existing access
  behavior for ordinary pages.
- With `restricted_web=1`, anonymous requests to unmarked XML pages invoke
  the existing login flow before page redirects, includes, or forms execute.
- An explicit `<w:public-access/>` permits anonymous page access unless
  `members-only` is also present. Use the `http://web.meon.eu/` namespace.
- Authenticated users retain existing access and role checks.
- Direct login, login invoked from a protected page, and logout work without
  access-control loops or requiring a public-access tag.
- Configuration applies independently to each website.
- Load the INI setting into a variable and test it with `if ($value)`.
  Use ordinary Perl truthiness, without strict `1` comparison or validation.
- Anonymous public timelines and directory listings must not expose protected
  entries, their content, teasers, bodies, or filenames. Empty members-only
  markers must protect entries consistently with direct page access.
- Custom 403/404/500 error pages must be publicly accessible.
- Password-reset and activation pages need explicit public-access markers.

### Confirmed decisions

- `members-only` wins when both markers are present, except for login/logout
  and the root custom 403/404/500 error pages.
- The initial restriction covers XML pages handled by the existing access
  check. Downloads, feeds, and separate API/search responses are outside this
  change. Document this boundary explicitly: static files are served before
  this check or through a separate action.
- On 2026-09-07, the user confirmed standard Perl truthiness for the setting:
  absent/undefined, empty string, and the string `0` are false; other strings
  such as `false`, `off`, `00`, and `2` are true. Read into a variable, then
  use `if ($value)`.
- Protected files and their content must be available only after login;
  public timelines and directory listings must respect this restriction.
  Fix the empty members-only inconsistency in this change. Whether this also
  broadens the earlier exclusion of non-XML downloads remains a question below.
- Error pages must also be public. Plan explicit exceptions for custom
  403/404/500 error rendering and preserve their HTTP status codes.
- Password-reset and activation pages require public-access markers.
- Search will be reworked separately. Its findings and follow-up work are
  recorded under `next TODOs` below.
- The existing authentication setup problem is a separate issue, outside
  restricted-web implementation. Track it under `next TODOs`; retain the
  documented test-only workaround for the current access tests.

## Code Context

- `lib/meon/Web/Controller/Root.pm`: `resolve_xml` uses the shared anonymous
  metadata decision; ordinary authenticated pages retain role checks.
  `_listing_visible` filters filenames and archive links. `login` forwards
  with `/login` in the stash; `logout` clears the session and redirects home.
- `lib/meon/Web/Config.pm`: already reads arbitrary keys from each site's
  `config.ini`; development can use `config_dev.ini` instead.
- `lib/meon/Web/env.pm`: `hostname_config` supplies the current site's config.
  `page_requires_login` shares marker precedence and Perl truthiness;
  `is_public_endpoint` recognizes resolved root login/logout/error XML files.
- `lib/meon/Web/TimelineEntry.pm`: `members_only` now checks marker presence,
  including empty elements. Controller timeline filtering uses the shared
  metadata decision so restricted-web defaults also apply.
- `t/tsp/etc/meon/web-config.ini` and `t/tsp/srv/www/meon-web/`: existing
  domain mapping and fixture layout for isolated website tests.
- `lib/meon/Web.pm` and `README`: existing project documentation entry points.
  There is no `srv/www/meon-web/localhost/config.ini` in this checkout.
- The separate, untracked `TODO-codereview.md` belongs to other work and must
  be preserved.

## Test Context

- Before implementation, run existing configuration/environment tests:
  `prove -l t/05_meon-Web-config.t t/06_meon-Web-env.t`.
- Add a focused controller access test, proposed path
  `t/07_meon-Web-Controller-Root-access.t`, and isolated fixtures under
  `t/tsp/srv/www/meon-web/`. Exercise actual controller access decisions and
  login forwarding, including detection of recursive login calls.
- Cover missing/0/1 configuration, anonymous/authenticated requests, unmarked
  pages, each marker separately, both markers with members-only winning,
  empty marker elements, and equivalent default/prefixed XML namespaces.
- Extend configuration coverage to empty strings and truthy strings such as
  `false`, `off`, `00`, and `2`, using the actual INI reader.
- Cover direct login, login from a protected URL, invalid and successful
  login, anonymous/authenticated logout, and the subsequent home request.
- Preserve role denial for authenticated users and verify site isolation.
- Check public pages containing timelines/includes/search results for
  exposure of protected content; add regression tests for any agreed changes.
- Turn timeline and directory-listing observations into assertions that
  anonymous users cannot see protected entries or filenames; verify logged-in
  access and empty members-only markers. Search changes are deferred.
- Add assertions for public unmarked custom error pages and public markers
  on password-reset/activation fixtures. Existing test results below predate
  the 2026-09-07 decisions and do not validate these additions yet.
- Check custom error pages and external-auth registration forwarding for
  recursion; keep login assets usable. Record any additional public markers
  required by the chosen scope.
- For this TODO-only edit, validate with `mdl TODO.md`. Root `README` gives
  no repository test command for Markdown changes.
- Baseline on 2026-09-06: the default `prove` cannot load `Test::Most` and
  runs no assertions. The installed Perlbrew Perl 5.40.1 passes both files
  (6 top-level tests). Reproduce with:

  ```sh
  PATH=/home/rob/perl5/perlbrew/perls/perl-5.40.1/bin:$PATH \
    prove -l t/05_meon-Web-config.t t/06_meon-Web-env.t
  ```

### Completed testing request (before implementation)

The user requested testing according to this plan and deferred new questions
to this file. Execute the testing work without intermediate approval stops.
Add executable acceptance tests against the current implementation; record
expected failures for the unimplemented feature. Production implementation
and unresolved policy decisions remain separate work.

- [x] Run the configuration/environment baseline with available dependencies.
- [x] Add isolated controller fixtures and verify the first acceptance failure.
- [x] Exercise the agreed access/authentication matrix and investigate the
  listing, include, error, and registration paths.
- [x] Record results, clarification questions, and validation limitations.
- [x] Validate and review the added tests and fixtures.

### Test results (2026-09-06)

- Added `t/07_meon-Web-Controller-Root-access.t` and three website configurations
  under `t/tsp/srv/www/meon-web/access_{restricted,disabled,missing}_t/`.
  The shared page/template fixtures live in `access_restricted_t`; the test
  copies fixtures into a temporary tree and creates page variants, profiles,
  and sessions there. It does not write to deployed websites.
- First red test verified: an anonymous request to the restricted home page
  returned its content instead of invoking login. The test failed two body
  assertions, with no compilation or request error.
- Final access suite: **FAIL**, 39 top-level tests, 30 passing and 9 failing.
  Its nested tests contain 412 assertions, with 44 failures. These are ordinary
  failures, not skipped tests or Perl TODO expectations.
- Eight failing groups cover missing default restriction, namespace variants,
  page-processing order, login through an unmarked protected URL, marked-login
  recursion, home after logout, and site isolation. `restricted_web` and
  `public-access` are not implemented in `Root.pm` yet.
- The ninth failing group is custom-error rendering: an authenticated user
  denied a role receives HTTP 500 instead of the custom 403 page. The first
  `resolve_xml` call moves `member-profile` out of the user's XML while
  building its response; the second call cannot find that profile. See
  `Root.pm`'s `$profile_el->appendChild($member_profile)` and
  `Member.pm::_build_member_meta`. This predates the proposed feature.
- Missing/0 configuration, authenticated access, empty/text markers,
  members-only precedence in either order, role denial, direct and forwarded
  members-only login, credential rejection/success, session restoration, and
  logout session invalidation pass with the authentication fixture setup below.
- The recursion guard detects repeated real login action calls and returns
  HTTP 508. Direct `/login` and login forwarded from `/members` both reach it
  when `login.xml` contains members-only, with or without public-access.
- Static login CSS and a non-XML content resource remain accessible.
- Six existing regression files pass: **33 top-level tests**. The member tests
  emit existing uninitialized-value warnings from `Member.pm` and
  `DateTime::Format::Strptime`; these are not assertion failures.
- Validation passed: `mdl TODO.md`, `perl -Ilib -c` for the new test,
  `xmllint --noout` for the three XML/XSLT fixture files, and the application's
  `Config::INI::Reader` for the four changed/added INI files. Generated page
  variants are parsed by `XML::LibXML` before writing and during requests.
- Added seven test/fixture entries to `MANIFEST`; a focused Python check
  verified that each entry is unique and names an existing file.
  `git diff --check` passed.
- Reviewed the test, fixture, and manifest changes with the code-review skill.
  No remaining findings in those changes. The application failures and test
  limitations remain recorded here. Perlcritic was unavailable and this
  repository has no `utils/perlcriticrc`; no Perlcritic result is claimed.

Reproduce the acceptance suite using the installed Perlbrew environment:

```sh
PATH=/home/rob/perl5/perlbrew/perls/perl-5.40.1/bin:$PATH \
  prove -lv t/07_meon-Web-Controller-Root-access.t
```

Reproduce the passing regression checks:

```sh
PATH=/home/rob/perl5/perlbrew/perls/perl-5.40.1/bin:$PATH \
  TEST_WITH_OPENSEARCH=0 prove -l \
  t/05_meon-Web-config.t t/06_meon-Web-env.t \
  t/10_meon-Web-Member.t t/10_meon-Web-TimelineEntry.t \
  t/64_meon-Web-Form-Search.t t/65_meon-Web-Search-Page.t
```

### Pre-implementation exposure observations and test limitations

- A public timeline currently exposes entries with no marker and entries with
  empty members-only. Text-valued members-only excludes entries. Public
  directory listings expose filenames in all three cases.
- A public page can include a fragment containing members-only and reveal its
  content. Includes use their own directory and do not run `resolve_xml` for
  each fragment; this is not a test of reading arbitrary content paths.
- A public search page renders a protected page's teaser when the backend
  returns it. This probe substitutes the external search service response and
  exercises the real form, response conversion, controller, and renderer.
  It does not establish which records a live search index contains.
- Unmarked custom 404/500 pages currently render their error bodies and keep
  their status. Public markers also work for those pages. The custom 403 case
  fails as described above. The deliberate 500 requests emit expected errors.
- External registration forwarding currently renders either an unmarked or
  public registration page. The test seeds only the session identity that a
  completed external authentication would provide; no identity-provider
  request or registration submission occurs.
- Observations with unresolved policy are diagnostic output, not assertions
  that content disclosure should remain allowed. Public error/registration
  rendering has assertions; unmarked variants report observations.
- The installed UserXML store creates a legacy default authentication realm
  without a credential verifier. Unmodified setup produced HTTP 500 on a
  password POST (`authenticate` called on an undefined verifier). The isolated
  test attaches the application's existing Password verifier from the members
  realm to the default realm. Password checks and cookie sessions then run
  through real implementations. Production configuration was not changed.
- The test uses a minimal XSLT template that exposes the response XML for
  assertions. It verifies CSS delivery, not browser layout or JavaScript.
  No live OpenSearch, feeds, downloads, or separate API endpoint suite ran.

### Scope choices for later review

1. Should fragments included by a public page inherit that page's visibility,
   or require their own public marker? The answer about separate search work
   did not settle include behavior. Implementation preserves existing behavior;
   public pages can still expose included fragments. Documented in README.
1. Does "files and their content" also extend protection to direct non-XML
   downloads, or retain the earlier XML-only boundary while filtering public
   listings? Implementation retains the earlier direct XML-only boundary;
   restricted public listings also hide non-XML filenames.
1. Should external-auth registration require a public-access marker, like
   password-reset and activation pages, or receive an automatic exception?
   Implementation requires the marker and returns 403 for a protected
   registration target, preventing recursive login. Recovery markers are
   confirmed. A broader automatic registration exception remains a possible
   later policy change.

### Authentication issue deferred

In the local test environment, submitting a username and password initially
crashed with HTTP 500 before the password could be checked. The application
had a password checker, but the default login setup was not connected to it.
The test connects the existing checker to that setup so it can exercise real
password authentication and sessions. This adjustment exists only in the test;
it does not fix or change the application.

This finding does not establish that login is broken on a deployed website.
Its configuration or installed dependency versions may differ. On 2026-09-07,
the user confirmed that investigation and repair belong to a separate issue.
This is not an unresolved scope question for restricted-web implementation.

The custom-403 profile-mutation defect was fixed during implementation because
it prevented the agreed error-page behavior. Authentication setup remains
separate as directed.

Decision update on 2026-09-07: updated this plan only; application tests were
not rerun. Markdown validation uses `mdl -r ~MD025 TODO.md` to preserve the
user-requested second top-level heading, `# next TODOs`. All other default
Markdown rules pass.

## Implementation results (2026-09-07)

- Implemented site-specific Perl-truthy restriction, public-access presence,
  members-only precedence, and resolved login/logout/error exceptions.
  Ordinary authenticated role checks are preserved. Error pages also bypass
  role metadata so an error page cannot recursively deny its own rendering.
- Cloned member-profile XML when building a response, preserving the user's
  source document for custom error rendering within the same request.
- Public timelines and directory listings now withhold protected XML content,
  titles, teasers, filenames, indexed subdirectories, and archive links.
  Empty members-only markers are consistent. Restricted anonymous directory
  listings also omit non-XML files and directories without an index;
  unreadable XML is omitted from all anonymous directory listings.
- A protected external registration target returns 403 without login loops;
  marked registration pages render. Existing include behavior is unchanged.
- Added marked password-reset/activation XML fixtures and verified that
  equivalent unmarked pages require login. No application recovery pages
  exist in this checkout to update; deployed pages need the documented markers.
- Added configuration examples, marker semantics, exceptions, listing behavior,
  and scope boundaries to `lib/meon/Web.pm` POD; regenerated `README`.
- TDD evidence: the pre-implementation suite reproduced 9 failing groups.
  The first implementation made all 39 original top-level tests pass.
  New listing and registration tests then failed as expected and passed after
  implementation. Additional error-role and archive-link tests exposed
  recursion/disclosure, then passed after the targeted fixes.
- Final focused regression run: **PASS**, 7 files, **76 top-level tests**.
  The access suite has **43 passing top-level tests**, including truthiness,
  default/prefixed namespaces, site isolation, login credentials and cookies,
  logout, roles, listings, error pages, recovery markers, and registration.
  Recovery-fixture changes were followed by another passing access-suite run.
- Validation: five XML/XSLT fixtures pass `xmllint`; four INI files pass
  `Config::INI::Reader`; nine added MANIFEST entries name unique existing files;
  README exactly matches `pod2text` output; POD syntax and `git diff --check`
  pass. Markdown uses `mdl -r ~MD025 TODO.md` for the requested headings.
- Existing member-test uninitialized-value warnings and deliberate HTTP 500
  test logs remain. POD checking reports a pre-existing whitespace-only line
  in the contributors section. These did not cause validation failures.
- Review with the code-review skill found no remaining defects in the scoped
  changes. Perlcritic is unavailable and no repository configuration exists.
  Live OpenSearch, external identity providers, and browser layout were not
  tested. The authentication fixture workaround remains intentionally in place.

The historical red-suite results above describe the state before implementation.
Authentication setup and search remain unchecked follow-up work below; include
policy and the direct-download boundary remain documented scope review points.

## Plan

Implementation authorized on 2026-09-07. Proceed through the approved work
without intermediate approval stops. Preserve the earlier direct XML-only
boundary and existing include behavior pending clarification. External
registration uses an explicit public marker; reject a protected registration
target without recursive login. Fix the profile-copy defect as necessary for
working custom error rendering. Authentication setup and search remain separate.

Execution order: make the existing red access/login/error tests pass; add red
truthiness and listing tests, implement shared metadata decisions and listing
filtering; verify public recovery markers and registration; document and run
regressions and validators. No new module is needed: `env.pm` will share the
metadata decision between direct page access and listing filters.

- [x] Analyze the original TODO, inspect relevant code/tests, add concrete
  actions, and identify unresolved requirements.
- [x] Resolve marker precedence and the scope of restricted resources with
  the user: members-only wins; cover XML pages using the existing check.
- [x] Resolve configuration semantics: load the INI value into a variable
  and use standard Perl truthiness with `if ($value)`.
- [x] Finalize access order: preserve authenticated role checks, keep
  login/logout and custom error rendering publicly accessible, then apply
  members-only precedence and the public-access presence marker to ordinary
  anonymous XML requests before metadata redirects, includes, and forms.
  Canonical URL redirects and non-XML handling currently occur earlier.
- [x] Inspect public listing/include paths, error rendering, and external-auth
  registration against the agreed scope; identify any required extra tests
  or public markers before implementation.
- [x] Run the existing configuration/environment tests and record the baseline.
- [x] Add isolated restricted/unrestricted website fixtures and write one
  failing controller test for an anonymous request to an unmarked page on
  a restricted website. Verify the expected failure before production edits.
- [x] Read the setting through `hostname_config` and minimally extend the
  existing access check to make that test pass.
- [x] Add failing tests and implement public-access and the agreed conflict
  rule, one behavior at a time; preserve existing role enforcement.
- [x] Add failing tests and implement login/logout exceptions, covering login
  forwarded from protected URLs and the redirect after logout.
- [x] Add failing tests and implement protected-entry filtering for public
  timelines and directory listings, including empty members-only markers.
- [x] Add failing tests and implement public custom error rendering while
  preserving HTTP status codes; fix the existing custom-403 profile-copy defect.
- [x] Add and verify public-access markers for password-reset/activation
  fixtures; document explicit registration markers and unchanged include
  behavior. No application recovery pages are shipped in this checkout.
- [x] Complete the test matrix, including per-site isolation and any agreed
  listing, error-page, or external-auth adjustments.
- [x] Document site configuration, default behavior, public-access XML,
  precedence, authentication exceptions, and the restriction boundary in
  the existing documentation. Add a config example without enabling the
  restriction for unrelated sites.
- [x] Run focused regression tests and validators for changed documentation,
  INI, and XML fixtures; record results and any limitations here.
- [x] Review the implementation with the code-review skill and clean up while
  keeping tests passing.

## Review completed (2026-09-07)

- [x] Apply code-review and TDDD to the working-tree implementation, tests,
  fixtures, manifest, and documentation. Preserve `TODO-codereview.md`.
- [x] Re-run focused regressions: 7 files, 76 top-level tests pass. Existing
  warnings and deliberate error logs remain as previously recorded.
- [x] Reproduce missed cases in an isolated copy of the access harness:
  `/tmp/meon-review-probes.t`, output `/tmp/meon-review-probes.log`.
  Three additional groups fail: raw XML disclosure, skipped public archives,
  and symlinked-login recursion. No production behavior changed during review.
- [x] Add end-of-file function POD for the new access/listing/test helpers
  and the changed TimelineEntry marker builder. Correct the README/POD to
  disclose the verified implementation gaps. Label old exposure observations
  as pre-implementation results. All five changed Perl files pass POD
  validation; README was regenerated with pod2text. Markdown validation
  (`mdl -r ~MD025 TODO.md`) and `git diff --check` pass. The existing POD
  whitespace warning remains; no executable behavior changed.
- [x] Record pending code corrections and supported refactoring separately
  under `Code-Review Plan`. The earlier "no remaining defects" assessment is
  superseded by these reproduced findings.
- [x] Apply the TDDD temporary-reference boundary: remove all references to
  this task file from durable POD, generated README text, and source comments.
  Keep the verified implementation gaps self-contained in POD and explain the
  authentication test workaround directly at its use site. A repository-wide
  case-insensitive search excluding active task-history files finds no remaining
  references. POD and test POD syntax, README regeneration/equality, Markdown,
  and `git diff --check` validation pass. The pre-existing whitespace-only POD
  warning in `lib/meon/Web.pm` remains.
- [x] Redo the review against `origin/master`, including the two branch commits,
  working-tree changes, and untracked access fixtures. The seven focused tests
  pass with 77 top-level tests. The isolated review probe still reproduces the
  three pending defects from review round 1 and fails only those three groups.
- [x] Add concise function POD for the changed `resolve_xml` and `login`
  controller methods. Tighten the durable wording for the raw-XML and symlink
  gaps in `lib/meon/Web.pm` and `env.pm`, and correct the access test's stale
  statement that listing policy remains unresolved. Regenerate `README`. All
  five reviewed Perl files and the access test pass POD validation; `README`
  matches `pod2text`. The post-edit access suite passes all 44 top-level tests;
  Markdown validation and `git diff --check` also pass.

Reuse assessment: existing access helpers should remain the shared policy.
No equivalent helper exists in the repository for public endpoint recognition.
The custom fixture copier was replaced with `Test::Dirs::temp_copy_ok` as
directed by the user; site-variant copies use its underlying
`File::Copy::Recursive::dircopy` inside temporary storage. Both direct test
dependencies are now declared. No new general-purpose module or CPAN
publication is needed.

Complexity assessment: `Root.pm::resolve_xml` combines access, forms, listings,
galleries, timelines, and member rendering. Limit this review's proposed
extraction to timeline navigation and listing visibility; do not refactor the
entire controller. The new helpers themselves are short and cohesive, although
`is_public_endpoint` describes routing more broadly than its filesystem check.

Validation gaps: Perlcritic and `utils/perlcriticrc` are unavailable. Live
search, external authentication, and browser behavior remain outside this
review. The authentication test workaround remains as explicitly deferred.

# next TODOs

- [ ] Investigate and repair the existing authentication setup separately.
  Local password login produced HTTP 500 because the default authentication
  realm lacked a credential verifier. Check application configuration and
  UserXML/Catalyst compatibility, reproduce without the test-only workaround,
  and verify password authentication and session restoration after repair.
  Relevant files: `lib/meon/Web.pm` and
  `t/07_meon-Web-Controller-Root-access.t`. Remove the workaround when the
  underlying issue is fixed. Deployed login behavior has not been verified.
- [ ] Rework search separately from restricted-web access control.
  A public XML search page currently renders a protected page's title and
  teaser when the backend returns that hit. The existing probe substitutes
  the backend response and runs the real form, response conversion,
  controller, and XSLT renderer; live index contents were not verified.
  Relevant files: `lib/meon/Web/Form/Search.pm`,
  `lib/meon/Web/SearchAPI/SearchResponse.pm`, `lib/meon/Web/SearchIndex.pm`,
  and `t/07_meon-Web-Controller-Root-access.t`.
  Define access filtering for anonymous and authenticated search, verify
  indexing/query behavior, and test titles, URLs, teasers, pagination counts,
  and separate search/API responses for protected-content disclosure.

# Code-Review Plan

## Fresh staged review (2026-09-08)

- [x] Review the complete staged diff afresh, trace access policy, direct XML,
  login/error forwarding, and listing/archive callers, and assess helper reuse.
  No new actionable code defects or supported refactoring suggestions found.
  Earlier findings and owner decisions below remain preserved.
- [x] Correct stale login-recursion and archive-navigation gap descriptions in
  `lib/meon/Web.pm`, regenerate `README`, and document the three changed
  navigation helpers in `Root.pm` POD. These review edits are unstaged;
  executable code and the index are unchanged.
- [x] Run focused regressions: seven files pass, 80 top-level tests, using
  Perlbrew Perl 5.40.1 and `TEST_WITH_OPENSEARCH=0`. Existing member warnings
  and deliberately triggered error logs remain. POD validation passes with
  the existing whitespace-only paragraph warning in `Web.pm`.
- [x] Compile suite passes all 84 module checks. Markdown validation
  (`mdl -r ~MD025 TODO.md`), generated README equality, and staged/unstaged
  whitespace checks pass.

Validation gaps: Perlcritic and `utils/perlcriticrc` are unavailable. No live
OpenSearch, external identity provider, or browser validation ran. The existing
authentication fixture workaround and deferred include/search boundaries
remain as documented above.

Reuse suggestions: none identified beyond the shared policy, fixture-copy,
and navigation helpers already present in the staged changes. No additional
CPAN dependency is justified by the reviewed functionality.

Code complexity refactoring: none identified within this diff. The extracted
navigation and visibility helpers have focused responsibilities; a broader
`resolve_xml` restructuring is outside this review's scope.

## Review round 1 (2026-09-07)

Decision: reuse suggestion approved on 2026-09-07; other newly identified code
corrections/refactoring still await approval.
Documentation corrections are completed review work, not pending code changes.

- [x] [HIGH] Raw XML bypasses the new restriction. The guard in
  `lib/meon/Web/Controller/Root.pm:262` is reached only for rendered pages;
  the pre-existing static fallback at line 126 serves page source first.
  Reproduced: anonymous `/default-unmarked.xml?t=1` on the restricted fixture
  returns HTTP 200 containing `MATRIX_PAGE_CONTENT`, while the rendered URL
  requires login. This is a pre-existing route that leaves the new feature's
  XML protection incomplete. Apply the shared policy before serving raw page
  XML, or reject direct page-source requests. Keep the explicitly excluded
  feeds/non-XML assets separate. Add anonymous/authenticated source-download
  tests, including members-only, role denial, and public-page policy.

  Completed 2026-09-07: direct XML is interpreted by default and uses the
  shared page policy. Only exact request paths listed as values under the
  current host's `[raw_xml]` section are served statically. The lookup is
  constructed lazily and cleared with the request environment. Tests cover
  anonymous and authenticated access, restricted defaults, members-only,
  public pages, role denial, arbitrary INI keys, configured raw XML, and host
  isolation. Non-XML static behavior remains unchanged.
- [x] [HIGH] Repeated login forwarding can recurse. Reproduced by moving
  `login.xml` to an unmarked shared file and symlinking it back: direct
  `/login` reaches the test's HTTP 508 recursion guard because the resolved
  target has no root endpoint exception. Per the owner decision on 2026-09-08,
  do not add symlink-specific access behavior. Immediately before the first
  detach to `/login`, set
  `meon::Web::env->stash->{login_in_progress}`. If a protected page reaches
  the same detach point again during that request, return a plain HTTP 403
  login-loop error without invoking login or custom error handling. Keep the
  existing resolved-file endpoint policy and filesystem containment behavior.
  Test direct and forwarded login loops, marked login targets, error paths
  that enter the same loop, and unaffected normal login behavior.

  The earlier symlink-specific implementation and its completed result were
  rejected by the owner on 2026-09-08 in favor of this request-wide invariant.

  Completed 2026-09-08: `resolve_xml` records `login_in_progress` in the
  request environment stash immediately before detaching to `/login`. A later
  login requirement returns a plain HTTP 403 login-loop response and withholds
  the protected bodies. Catalyst's 500 handler preserves that response while
  unwinding its forwarded action. No endpoint or symlink classifier was added;
  the existing resolved-file exception policy remains unchanged. The access
  test adds 21 assertions covering direct and forwarded login, 403/404/500
  paths entering the loop, request-state reset, and a public login target.
  The access suite passes with 46 top-level tests; seven focused regression
  files pass with 80 top-level tests, and the compile suite passes 84 module
  checks. Changed Perl and test files pass syntax and POD validation;
  whitespace and Markdown validation pass. Existing member-test warnings and
  deliberate custom-500 logs remain unchanged.
- [x] [MEDIUM] Archive navigation stops at a protected neighbour.
  `lib/meon/Web/Controller/Root.pm:487` and line 494 filter only the first
  candidate from `_older_entries`/`_newer_entries`. Reproduced: public 2024,
  private 2025, current public 2026, private 2027, public 2028 produces neither
  navigation link. Continue traversal until a visible archive or exhaustion;
  test both directions, multiple hidden neighbours, and authenticated access.

  Approved 2026-09-08: preserve the existing numeric archive traversal and
  `_listing_visible` policy. Allow `_older_entries` and `_newer_entries` to
  start from an optional archive directory, then advance past hidden results
  until a visible archive is found or traversal is exhausted. Keep the
  separate navigation-consolidation suggestion below out of this correction.
  Add controller tests for anonymous traversal across multiple hidden archives,
  exhausted traversal, and authenticated access to immediate protected
  neighbours.

  Completed 2026-09-08: older/newer traversal accepts an optional archive
  directory and resumes from each protected candidate until a visible archive
  is found or no candidate remains. The controller test's two anonymous
  traversal assertions failed before implementation and pass afterward;
  exhaustion and authenticated immediate-neighbour behavior also pass. Seven
  focused regression files pass with 80 top-level tests, and the compile suite
  passes 84 module checks. Changed Perl and test files pass syntax and POD
  validation; Markdown and `git diff --check` pass. Existing member-test
  warnings and deliberate custom-500 logs remain unchanged.
- [x] [Reuse suggestion] Replace the custom fixture copier at
  `t/07_meon-Web-Controller-Root-access.t:508` with the existing
  `Test::Dirs::temp_copy_ok`, as directed by the user. Keep its returned
  temporary-directory object alive for cleanup, use its underlying
  `File::Copy::Recursive::dircopy` for site variants within that isolated tree,
  declare both direct test dependencies, and run the access test and focused
  regressions.

  Completed 2026-09-07: imported `temp_copy_ok` and retained its temporary
  directory object for cleanup; removed `copy_tree`, `File::Find`, and its POD.
  Site variants use `dircopy` only inside the isolated temporary fixture tree.
  Added `Test::Dirs` and `File::Copy::Recursive` to `build_requires`. The access
  suite passes with 44 top-level tests, including the helper's copy assertion;
  the full focused regression passes with 7 files and 77 top-level tests.
  Build.PL and test syntax, test POD, Markdown, and `git diff --check` pass.
- [x] [Complexity suggestion] Consolidate the duplicated older/newer link
  construction at `Root.pm:487` and line 494 into one focused navigation helper
  as part of the traversal correction. Keep `_listing_visible` as the shared
  visibility predicate. Rename `is_public_endpoint` to reflect logical public
  page matching if that correction changes its contract; update callers/POD
  and retain routing, exception, and listing regression coverage.

  Approved 2026-09-08: extract `_append_timeline_navigation` to share candidate
  traversal and link creation for both directions. Preserve `_listing_visible`
  and the completed traversal correction. The public exception contract remains
  resolved-file matching, so its conditional rename does not apply. Existing
  traversal tests supply regression coverage for this behavior-preserving
  refactor; their failing-before-fix result is recorded above. Baseline:
  environment and controller access tests pass (2 files, 50 top-level tests).

  Completed 2026-09-08: both directions use `_append_timeline_navigation` for
  visibility traversal and XML link creation. `_listing_visible` and the
  resolved-file public exception helper/callers/POD retain their contracts.
  Seven focused regression files pass (80 top-level tests), including routing,
  exceptions, listings, traversal exhaustion, hidden archives, and authenticated
  neighbours. Perl syntax, POD, and whitespace validation pass. Markdown
  passes with MD025 excluded for the existing multiple top-level headings;
  plain `mdl TODO.md` reports those two existing MD025 violations.
  Existing member warnings and intentional custom-500 logs remain unchanged.

## Review round 2 (2026-09-07)

Decision: no executable code changes were authorized for this review round.
The three defect corrections and the related complexity refactoring remain
unapproved.

No additional code action points were found. The isolated probe revalidated all
three unchecked defects in [review round 1](#review-round-1-2026-09-07): raw XML
disclosure, symlinked public-endpoint recursion, and archive traversal stopping
at a protected neighbour. The round 1 checkboxes remain the source of truth to
avoid duplicating pending work.

## Review round 3 (2026-09-07)

Decision: documentation-only review requested by the user.

- [x] Simplify the `RESTRICTED WEBSITES` POD without changing its documented
  behavior. Remove test-fixture detail and internal helper names; retain the
  configuration contract, marker precedence, public exceptions, listing
  behavior, enforcement boundary, and known gaps. Regenerate and validate the
  README rendering.

  Completed 2026-09-07: `README` matches `pod2text`; POD and Perl syntax,
  Markdown, and `git diff --check` pass. `podchecker` still reports the existing
  whitespace-only line outside the reviewed section but confirms valid POD.

## Raw XML allowlist implementation (2026-09-07)

Decision approved by the user on 2026-09-07:

```ini
[raw_xml]
file.1 = /sitemap.xml
rss = /rss.xml
atom_feed = /atom.xml
```

- Configuration keys are arbitrary labels and are ignored. Only section values
  are used.
- `meon::Web::env` lazily constructs a lookup hash from those values for the
  current host/request.
- A direct `.xml` request is served as a static file only when its request path
  matches the lookup. Every unlisted `.xml` file is interpreted as a page and
  passes through the existing anonymous, members-only, public-access, and role
  policies.
- Non-XML static-file behavior is unchanged. XML feeds must be explicitly
  allowlisted; the resulting backward-incompatible default is accepted.
- Tests cover anonymous and authenticated direct `.xml` requests, restricted
  defaults, members-only, role denial, public pages, configured raw XML,
  arbitrary configuration keys, and per-host isolation.

Relevant files: `lib/meon/Web/env.pm`,
`lib/meon/Web/Controller/Root.pm`,
`t/06_meon-Web-env.t`, `t/07_meon-Web-Controller-Root-access.t`, host fixture
`config.ini` files, `lib/meon/Web.pm`, and generated `README`.

- [x] Investigate and reproduce the raw XML bypass and existing routing order.
- [x] Agree the value-only `[raw_xml]` allowlist design and document it here.
- [x] Run the focused baseline tests. The configuration, environment, and
  controller access suites pass: 3 files, 50 top-level tests.
- [x] Add failing tests for lazy allowlist construction and raw/interpreted XML
  routing across authentication and host-policy cases. Before implementation,
  the environment method was absent and the controller test failed 10 of its
  27 new assertions for source exposure, missing role enforcement, and host
  isolation.
- [x] Implement the lazy per-host lookup and allowlist-gated raw XML routing.
  The environment and controller access suites pass: 2 files, 49 top-level
  tests.
- [x] Document the configuration and remove the obsolete known-gap text.
  The POD documents exact-path values, arbitrary labels, per-host behavior,
  feed opt-in, and the deliberate access-policy bypass for public raw files;
  `README` was regenerated from it.
- [x] Run focused regressions plus Perl, POD, INI, XML, Markdown, generated
  README, manifest, and whitespace validation as applicable. Seven focused
  files pass with 79 top-level tests. Changed Perl and test files pass syntax;
  POD, the changed INI file, Markdown, generated README equality, and
  `git diff --check` pass. No persistent XML or manifest entries were added.
  Existing member-test warnings, deliberate custom-500 logs, the `env.pm`
  standalone compile redefinition warnings, and the known whitespace-only POD
  warning remain unchanged.
