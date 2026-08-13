import csv
import json
import os
from litellm import completion
from dotenv import load_dotenv

load_dotenv()

VM_LIST_FILE = "vm_list.csv"
VM_CSV_FIELDS = ["type", "name", "vm_name", "hash", "user", "password", "source", "link"]


def ask_vm_names(prompt):
    response = completion(
        model="groq/openai/gpt-oss-120b",
        fallbacks=["groq/openai/gpt-oss-20b"],
        messages=[
            {"role": "user", "content": prompt},
        ],
        response_format={
            "type": "json_schema",
            "json_schema": {
                "name": "vm_names",
                "schema": {
                    "type": "object",
                    "additionalProperties": {
                        "type": "string"
                    },
                },
            },
        },
    )
    content = response.choices[0].message.content
    return json.loads(content)


def vagrant_prompt(vagrant_boxes):
    return f"""I have the following list of Vagrant boxes: {vagrant_boxes}.
Please provide the names of the virtual machines associated with each Vagrant box.
The output should be in JSON format, where each key is a Vagrant box and the corresponding value is the virtual machine name associated with that box.
The virtual machine names must follow the format: "osFamily_osVersion" and should be unique for each Vagrant box. Example: "ubuntu_focal64", "centos_7", "windows_10", "macos_10.15", "android_9.0".

OUTPUT FORMAT:
You must respond ONLY with a valid JSON object. Do not include explanations or markdown backticks.
The JSON structure must be:
{{
"vagrant_box_1": "vm_name_1",
"vagrant_box_2": "vm_name_2",
...
}}
"""


def image_prompt(zip_names):
    return f"""I have the following list of VM image zip file names: {zip_names}.
Please suggest a virtual machine name for each zip file, based on the operating system and version implied by its file name.
The output should be in JSON format, where each key is a zip file name and the corresponding value is the suggested virtual machine name.
The virtual machine names must follow the format: "osFamily_osVersion" and should be unique for each zip file. Example: "ubuntu_focal64", "centos_7", "windows_10", "macos_10.15", "android_9.0".

OUTPUT FORMAT:
You must respond ONLY with a valid JSON object. Do not include explanations or markdown backticks.
The JSON structure must be:
{{
"zip_file_1": "vm_name_1",
"zip_file_2": "vm_name_2",
...
}}
"""


def process_vm_list(path):
    with open(os.path.expanduser(path), newline="") as f:
        rows = list(csv.DictReader(f))

    missing_vagrant = [
        row["name"] for row in rows
        if row.get("type", "").strip() == "vagrant" and not row.get("vm_name", "").strip()
    ]
    missing_image = [
        row["name"] for row in rows
        if row.get("type", "").strip() == "image" and not row.get("vm_name", "").strip()
    ]

    if not missing_vagrant and not missing_image:
        print("All rows already have a vm_name. Nothing to do.")
        return

    suggestions = {}
    if missing_vagrant:
        try:
            suggestions.update(ask_vm_names(vagrant_prompt(missing_vagrant)))
        except json.JSONDecodeError:
            print("Could not parse the AI response for Vagrant boxes as JSON. Those rows were left unchanged.")
    if missing_image:
        try:
            suggestions.update(ask_vm_names(image_prompt(missing_image)))
        except json.JSONDecodeError:
            print("Could not parse the AI response for image zips as JSON. Those rows were left unchanged.")

    for row in rows:
        if not row.get("vm_name", "").strip():
            row["vm_name"] = suggestions.get(row["name"], row.get("vm_name", ""))

    tmp_path = path + ".tmp"
    with open(tmp_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=VM_CSV_FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    os.remove(path)
    os.rename(tmp_path, path)


def main():
    process_vm_list(VM_LIST_FILE)


if __name__ == "__main__":
    main()
