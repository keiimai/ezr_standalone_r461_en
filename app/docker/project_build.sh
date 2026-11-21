# --- Build steps the research project adds (Layers 4–5 extension point; runs as root with sh -eu, and a failure stops the build) (DOCKER.md §2) ---
set -eu
page=/usr/lib/rstudio-server/www/index.htm
sed -i -e '0,/<html lang="en">/s//<html lang="en" translate="no">/' \
       -e '0,/<head>/s//<head>\n  <meta name="google" content="notranslate" \/>/' "$page"
grep -q '<html lang="en" translate="no">' "$page"
grep -q '<meta name="google" content="notranslate" />' "$page"
