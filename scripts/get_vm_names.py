import argparse
import json
import os
from litellm import completion
from dotenv import load_dotenv

load_dotenv()

with open(os.path.expanduser("vagrant_list.txt"), "r") as f:
    vagrant_boxes = [line.strip() for line in f if line.strip()]
    f.close()


prompt = f"""I have the following list of Vagrant boxes: {vagrant_boxes}.
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

response = completion(
    model="groq/openai/gpt-oss-120b",
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

with open("vagrant_list_temp.txt", "w") as f:
    try:
        data = json.loads(content)
        for k, v in data.items():
            f.write(f"{k};{v}\n")   
    except json.JSONDecodeError:
        f.write(content)


os.remove("vagrant_list.txt")
os.rename("vagrant_list_temp.txt", "vagrant_list.txt")



