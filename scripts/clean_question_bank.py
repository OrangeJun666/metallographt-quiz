import json
import re
import shutil
import zipfile
from datetime import datetime
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DOCX_PATH = ROOT / "金相大会题库.docx"
OUTPUT_PATH = ROOT / "data" / "question_bank.cleaned.json"
REPORT_PATH = ROOT / "data" / "clean_report.txt"
IMAGE_DIR = ROOT / "assets" / "images"

NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "pr": "http://schemas.openxmlformats.org/package/2006/relationships",
}
OPTION_LABELS = "ABCDEFG"


def normalize_line(text: str) -> str:
    t = text.lstrip("\ufeff")
    t = re.sub(r"\s+", " ", t).strip()
    t = re.sub(r"^\.+\s*(\d+)", r"\1", t)
    t = re.sub(r"^(\d+)\s+、", r"\1、", t)
    t = re.sub(r"^(\d+)\s+\.\s*", r"\1.", t)
    t = re.sub(r"^答案\s*[：:]\s*", "答案：", t)
    return t.strip()


def normalize_option_chars(text: str) -> str:
    trans = str.maketrans({
        "Ａ": "A", "Ｂ": "B", "Ｃ": "C", "Ｄ": "D", "Ｅ": "E", "Ｆ": "F", "Ｇ": "G",
        "А": "A", "В": "B", "С": "C", "Д": "D", "Е": "E", "Ф": "F", "Г": "G",
    })
    return text.translate(trans)


def extract_images_and_relationships() -> dict[str, str]:
    if not DOCX_PATH.exists():
        raise FileNotFoundError(f"DOCX not found: {DOCX_PATH}")

    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    for old_file in IMAGE_DIR.glob("*"):
        if old_file.is_file():
            old_file.unlink()

    rel_map: dict[str, str] = {}
    with zipfile.ZipFile(DOCX_PATH, "r") as zf:
        rel_xml = zf.read("word/_rels/document.xml.rels")
        rel_root = ET.fromstring(rel_xml)
        for rel in rel_root.findall("pr:Relationship", NS):
            rid = rel.attrib.get("Id")
            target = rel.attrib.get("Target", "")
            if rid and target.startswith("media/"):
                rel_map[rid] = Path(target).name

        for info in zf.infolist():
            if info.filename.startswith("word/media/") and not info.is_dir():
                dest = IMAGE_DIR / Path(info.filename).name
                with zf.open(info, "r") as src, open(dest, "wb") as dst:
                    shutil.copyfileobj(src, dst)

    return rel_map


def extract_paragraph_lines(rel_map: dict[str, str]) -> list[str]:
    with zipfile.ZipFile(DOCX_PATH, "r") as zf:
        doc_xml = zf.read("word/document.xml")
    doc_root = ET.fromstring(doc_xml)

    lines: list[str] = []
    for p in doc_root.findall(".//w:body/w:p", NS):
        parts: list[str] = []
        for r in p.findall("w:r", NS):
            t_nodes = r.findall("w:t", NS)
            if t_nodes:
                parts.append("".join((t.text or "") for t in t_nodes))

            for blip in r.findall(".//a:blip", NS):
                rid = blip.attrib.get(f"{{{NS['r']}}}embed")
                image_name = rel_map.get(rid or "", "")
                if image_name:
                    parts.append(f" [[IMG:{image_name}]] ")

        line = normalize_line("".join(parts))
        if line:
            lines.append(line)
    return lines


def split_option_line(line: str):
    normalized = normalize_option_chars(line)
    normalized = re.sub(r"([A-G])\s*[\.．、:：\)]\s*", r"\1. ", normalized)

    marks = list(re.finditer(r"([A-G])\.\s*", normalized))
    if not marks:
        return []

    out = []
    for i, m in enumerate(marks):
        label = m.group(1)
        start = m.end()
        end = marks[i + 1].start() if i + 1 < len(marks) else len(normalized)
        text = normalized[start:end].strip(" 。;；")
        # 判断是否为图片型选项
        # 只要内容为图片型（如 image1.png]] 或 [[IMG:xxx]]），都跳过
        img_like = re.fullmatch(r"\s*(\[\[IMG:[^\]]+\]\]|image\d+\.(png|jpg|jpeg|gif|bmp)\]\])\s*", text, re.IGNORECASE)
        if img_like:
            continue
        # 剥离图片标记
        clean_text = re.sub(r"\[\[IMG:[^\]]+\]\]", " ", text).strip()
        # 剥离 image*.png]] 结尾
        clean_text = re.sub(r"image\d+\.(png|jpg|jpeg|gif|bmp)\]\]$", "", clean_text, flags=re.IGNORECASE).strip()
        if clean_text:
            out.append((label, clean_text))
    return out


def pull_images(text: str) -> tuple[str, list[str]]:
    found = re.findall(r"\[\[IMG:([^\]]+)\]\]", text)
    cleaned = re.sub(r"\[\[IMG:[^\]]+\]\]", " ", text)
    cleaned = normalize_line(cleaned)
    imgs = [f"assets/images/{name}" for name in found]
    return cleaned, list(dict.fromkeys(imgs))


def main() -> None:
    rel_map = extract_images_and_relationships()
    lines = extract_paragraph_lines(rel_map)

    header_re = re.compile(r"^(\d+)\s*[、\.．]\s*(.+)$")
    answer_re = re.compile(r"^答案：\s*([A-G]+)\s*$")
    explain_re = re.compile(r"^解析[：:]\s*(.*)$")

    blocks = []
    cur = None
    for line in lines:
        hm = header_re.match(line)
        if hm:
            if cur:
                blocks.append(cur)
            cur = {
                "original_no": int(hm.group(1)),
                "title": hm.group(2).strip(),
                "body": [],
            }
            continue
        if cur:
            cur["body"].append(line)
    if cur:
        blocks.append(cur)

    questions = []
    issues = []
    total_images_used = 0

    for idx, block in enumerate(blocks, start=1):
        question = normalize_option_chars(block["title"])
        options = {}
        answer = ""
        explanation_parts = []
        image_paths: list[str] = []
        pending_label = None

        q_text, q_imgs = pull_images(question)
        question = q_text
        image_paths.extend(q_imgs)

        for line in block["body"]:
            line = normalize_option_chars(line)
            am = answer_re.match(line)
            if am:
                answer = am.group(1)
                continue

            em = explain_re.match(line)
            if em:
                text, imgs = pull_images(em.group(1).strip())
                if text:
                    explanation_parts.append(text)
                image_paths.extend(imgs)
                continue

            split_opts = split_option_line(line)
            if split_opts:
                for label, text in split_opts:
                    clean_text, imgs = pull_images(text)
                    options[label] = clean_text
                    image_paths.extend(imgs)
                    pending_label = label
                continue

            clean_line, imgs = pull_images(line)
            image_paths.extend(imgs)

            if pending_label and not clean_line.startswith("答案"):
                options[pending_label] = f"{options[pending_label]} {clean_line}".strip()
                continue

            if not options:
                question = f"{question} {clean_line}".strip()
            elif clean_line:
                explanation_parts.append(clean_line)

        option_list = [
            {"key": k, "text": options[k]}
            for k in OPTION_LABELS
            if k in options
        ]

        unique_images = list(dict.fromkeys(image_paths))
        total_images_used += len(unique_images)

        if len(option_list) < 2:
            issues.append(f"Q{idx} options_lt_2 original_no={block['original_no']}")
        if not answer:
            issues.append(f"Q{idx} no_answer original_no={block['original_no']}")
        elif not re.fullmatch(r"[A-G]+", answer):
            issues.append(f"Q{idx} invalid_answer={answer} original_no={block['original_no']}")

        questions.append(
            {
                "id": idx,
                "original_no": block["original_no"],
                "type": "multiple" if len(answer) > 1 else "single",
                "question": question,
                "images": unique_images,
                "options": option_list,
                "answer": answer,
                "explanation": " ".join(explanation_parts).strip(),
            }
        )

    extracted_images = len(list(IMAGE_DIR.glob("*")))
    payload = {
        "meta": {
            "source": DOCX_PATH.name,
            "cleaned_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "total": len(questions),
            "issue_count": len(issues),
            "images_extracted": extracted_images,
            "images_used_in_questions": total_images_used,
            "supported_options": OPTION_LABELS,
        },
        "questions": questions,
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    report_lines = [
        f"total_questions={len(questions)}",
        f"issues={len(issues)}",
        f"images_extracted={extracted_images}",
        f"images_used_in_questions={total_images_used}",
        "",
        "top_issues:",
    ]
    report_lines.extend(issues[:120] if issues else ["none"])
    REPORT_PATH.write_text("\n".join(report_lines), encoding="utf-8")

    print(f"Cleaned questions: {len(questions)}")
    print(f"Issue count: {len(issues)}")
    print(f"Images extracted: {extracted_images}")
    print(f"JSON: {OUTPUT_PATH}")
    print(f"Report: {REPORT_PATH}")


if __name__ == "__main__":
    main()
