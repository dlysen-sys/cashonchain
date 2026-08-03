# Archived pages / sections

Holding area for the **initial scaffold pages and section bodies** as they get replaced by
real Cash On Chain (COC) content.

## Workflow (archive-on-replace)
COC starts on the workspace template shell with placeholder pages so the app builds and runs
from day one. As each page is rebuilt for COC:

1. Build the new COC page/section.
2. Move the old file here instead of deleting it:
   - page components → `src/pages/archived/`
   - section bodies (`*.html`) and section wrappers → `src/sections/archived/`
3. Update the route / import to point at the new page.
4. Note the swap in the session file.

Nothing in these `archived/` folders is imported by the live app — they are reference only,
kept so we can diff against the original scaffold while building COC out.

> Frontend design is the commercial ThemeForest theme "Patrick — Personal CV/vCard React
> Template" (item 35737202). A license is required before publishing anything derived from it.
