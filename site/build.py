"""Build the static project page from the shared README; never publish or read secrets."""
import argparse
from html import escape
from pathlib import Path
import re
import shutil
from urllib.parse import urlsplit
from markdown_it import MarkdownIt

ROOT = Path(__file__).resolve().parents[1]
REPO = "https://github.com/Q1ngSong/Tangler"


def rendered_readme():
    text = (ROOT / "README.md").read_text(encoding="utf-8")
    start, end = "<!-- development-only:start -->", "<!-- development-only:end -->"
    lines, hidden = [], False
    for line in text.splitlines(keepends=True):
        if line.strip() == start:
            if hidden:
                raise ValueError("Unbalanced development-only README markers")
            hidden = True
        elif line.strip() == end:
            if not hidden:
                raise ValueError("Unbalanced development-only README markers")
            hidden = False
        elif not hidden:
            lines.append(line)
    if hidden:
        raise ValueError("Unbalanced development-only README markers")
    text = "".join(lines)
    first_heading = re.search(r"^## ", text, re.M)
    if first_heading is None:
        raise ValueError("README must contain a level-two heading")
    parser = MarkdownIt("commonmark", {"html": True}).enable("table")
    tokens = parser.parse(text[first_heading.start():])
    headings = []
    seen = set()
    for i, token in enumerate(tokens):
        if token.type == "heading_open":
            title = tokens[i + 1].content
            anchor = re.sub(r"[^\w -]", "", title.lower()).replace(" ", "-")
            if anchor in seen:
                raise ValueError("Duplicate heading anchor: " + anchor)
            seen.add(anchor)
            token.attrSet("id", anchor)
            if token.tag == "h2":
                headings.append((anchor, title))
        for child in token.children or []:
            if child.type == "link_open":
                href = child.attrGet("href")
                if href and not urlsplit(href).scheme and not href.startswith(("#", "//")):
                    if not (ROOT / href.split("#")[0]).is_file():
                        raise ValueError("Missing README link target: " + href)
                    child.attrSet("href", REPO + "/blob/main/" + href)
            if child.type == "image":
                src = child.attrGet("src")
                if not src.startswith("docs/assets/") or not (ROOT / src).is_file():
                    raise ValueError("README illustrations must be shared local assets")
                child.attrSet("loading", "lazy")
                child.attrSet("decoding", "async")
    html = parser.renderer.render(tokens, parser.options, {})
    toc = "\n".join(f'<a href="#{anchor}">{escape(title)}</a>' for anchor, title in headings)
    return html, toc


def build(check=False, output=None):
    html, toc = rendered_readme()
    template = (ROOT / "site/index.html").read_text(encoding="utf-8")
    if template.count("__README__") != 1 or template.count("__TOC__") != 1:
        raise ValueError("Website template must contain exactly one content and navigation slot")
    result = template.replace("__README__", html).replace("__TOC__", toc)
    index = ROOT / "index.html"
    if check:
        if not index.exists() or index.read_text(encoding="utf-8") != result:
            raise SystemExit("Website is stale: run python3 site/build.py and commit index.html")
        print("Website matches README and template")
    else:
        index.write_text(result, encoding="utf-8")
        print("Generated index.html")
    if output:
        target = Path(output).resolve()
        build_root = (ROOT / "build").resolve()
        if build_root not in target.parents or target == build_root:
            raise ValueError("Site output must be a subdirectory of this checkout's build/")
        if target.exists() and any(target.iterdir()):
            raise ValueError("Site output must be empty: " + str(target))
        target.mkdir(parents=True, exist_ok=True)
        for name in ["index.html", ".nojekyll", "site/style.css", "site/main.js", "site/mark.svg"]:
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        for source in sorted((ROOT / "docs/assets").glob("*.svg")):
            destination = target / "docs/assets" / source.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
        print("Static-only Pages artifact:", target)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--output", help="New or empty build/ subdirectory for the Pages artifact")
    args = parser.parse_args()
    build(args.check, args.output)
