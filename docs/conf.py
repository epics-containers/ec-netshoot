"""Configuration file for the Sphinx documentation builder."""

from pathlib import Path
from subprocess import check_output

project = "ec-netshoot"
github_user = "epics-containers"
github_repo = "ec-netshoot"

# This repo has no python package to read a version from, so take it from git.
root = Path(__file__).absolute().parent.parent
try:
    version = check_output(
        "git describe --tags --always".split(), cwd=root, text=True
    ).strip()
except Exception:
    version = "main"
release = version

extensions = [
    "sphinx_copybutton",
    "sphinx_design",
    "myst_parser",
]

myst_enable_extensions = ["colon_fence"]

nitpicky = True
master_doc = "index"
exclude_patterns = ["_build"]
pygments_style = "sphinx"

linkcheck_ignore = [r"http://localhost:\d+/"]

copybutton_prompt_text = r">>> |\.\.\. |\$ |In \[\d*\]: | {2,5}\.\.\.: | {5,8}: "
copybutton_prompt_is_regexp = True

# -- HTML output -------------------------------------------------------------

html_theme = "pydata_sphinx_theme"
html_theme_options = {
    "logo": {"text": project},
    "use_edit_page_button": True,
    "github_url": f"https://github.com/{github_user}/{github_repo}",
    "switcher": {
        "json_url": f"https://{github_user}.github.io/{github_repo}/switcher.json",
        "version_match": version,
    },
    "check_switcher": False,
    "navbar_end": ["theme-switcher", "icon-links", "version-switcher"],
    "navigation_with_keys": False,
}

html_context = {
    "github_user": github_user,
    "github_repo": github_repo,
    "github_version": version,
    "doc_path": "docs",
}

html_show_sphinx = False
html_show_copyright = False
