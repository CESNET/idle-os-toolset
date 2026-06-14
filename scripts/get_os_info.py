import argparse
import os
import json
import subprocess
import shlex
from litellm import completion
from dotenv import load_dotenv

load_dotenv()

home=os.path.expanduser("~")
os_info_path=home+"/os_info/"
vm_list_path=home+"/vm_list.md"

def generate_commands(vagrant_box, vm_name):
    prompt = f"""
            I am utilizing the following Vagrant box: https://portal.cloud.hashicorp.com/vagrant/discover/{vagrant_box}. 
            
            Provide the necessary commands to obtain the OS information. The commands should return the output in the terminal. The OS information should include details such as OS family, OS type, and OS version.
            
            OUTPUT FORMAT:
            You must respond ONLY with a valid JSON object. Do not include explanations or markdown backticks.
            The JSON structure must be:
            {{
            "Commands": ["command1", "command2"]
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
                "name": "commands",
                "schema": {
                    "type": "object",
                    "properties": {
                        "Commands": {
                            "type": "array",
                            "items": {"type": "string"}
                        }
                    },
                    "required": ["Commands"],
                },
            },
        },
    )

    os.makedirs(os_info_path + vm_name, exist_ok=True)
    with open(os_info_path + vm_name + "/commands.json", "w") as f:
        try:
            json_data = json.loads(response.choices[0].message.content)
            json.dump(json_data, f, indent=4)
        except json.JSONDecodeError:
            f.write(response.choices[0].message.content)

def execute_commands(vagrant_box, vm_name):

    with open(os_info_path + vm_name + "/commands.json", "r") as f:
        data = json.load(f)
        commands = data.get("Commands", [])
        command_outputs = {}
        print(f"Executing commands for {vm_name}:")
        if "android" in vm_name.lower() or "android" in vagrant_box.lower():
            os.system("adb connect localhost:5555")
            remote_command = "adb -s localhost:5555 shell '{}'"
        elif "windows" in vm_name.lower() or "windows" in vagrant_box.lower():
            remote_command = "vagrant winrm -c '{}'"
        else:
            remote_command = "vagrant ssh -c '{}'"
        for command in commands:
            try:
                command_to_run = shlex.split(remote_command.format(command))
                result = subprocess.run(command_to_run, capture_output=True, text=True)
                command_outputs[command] = result.stdout

            except Exception as e:
                print(f"Error executing command '{command}': {e}")

    with open(os_info_path + vm_name + "/commands_execute.json", "w") as f:
        json.dump(command_outputs, f, indent=4)


def get_os_info(vagrant_box, vm_name):
    with open(os_info_path + vm_name + "/commands_execute.json", "r") as f:
        command_outputs = json.load(f)

    with open(os_info_path + vm_name + "/commands.json", "r") as f:
        commands = json.load(f).get("Commands", [])

    with open(vm_list_path, "r") as f:
        vm_list = f.read()


    prompt = f"""
            I have executed the following commands {commands} and obtained the following outputs: {json.dumps(command_outputs)}.
            Analyze the command outputs and provide a summary of the OS information. You must respond with the Os_Family, Os_Type and Os_Version.
            OUTPUT FORMAT:
            You must respond ONLY with a valid JSON object. Do not include explanations or markdown backticks.
            The JSON structure must be:
            {{
            "Os_Family": "...",
            "Os_Type": "...",
            "Os_Version": "..."
            }}
            The values should be similar to the values of this file: {vm_list}.
            """

    response = completion(
        model="groq/openai/gpt-oss-120b",
        messages=[
            {"role": "user", "content": prompt},
        ],
        response_format={
            "type": "json_schema",
            "json_schema": {
                "name": "os_info",
                "schema": {
                    "type": "object",
                    "properties": {
                        "Os_Family": {"type": "string"},
                        "Os_Type": {"type": "string"},
                        "Os_Version": {"type": "string"},
                    },
                    "required": ["Os_Family", "Os_Type", "Os_Version"],
                },
            },
        },
    )

    with open(os_info_path + vm_name + "/os_info.json", "w") as f:
        try:
            json_data = json.loads(response.choices[0].message.content)
            json.dump(json_data, f, indent=4)
        except json.JSONDecodeError:
            f.write(response.choices[0].message.content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Get OS information of a vagrant box."
    )
    parser.add_argument(
        "-v", "--vagrant_box",
        type=str,
        help="Vagrant box name (example: datacastle/windows7)",
    )
    parser.add_argument(
        "-b", "--vm_name",
        type=str,
        help="Virtual machine name (example: windows_windows7)",
    )

    args = parser.parse_args()

    print(f"Getting OS info commands for virtual machine: {args.vm_name} with Vagrant box: {args.vagrant_box}")
    generate_commands(args.vagrant_box,args.vm_name)
    print(f"Commands saved to {os_info_path + args.vm_name + '/commands.json'}")
    execute_commands(args.vagrant_box,args.vm_name)
    print(f"Command outputs saved to {os_info_path + args.vm_name + '/commands_execute.json'}")
    get_os_info(args.vagrant_box,args.vm_name)
    print(f"OS information saved to {os_info_path + args.vm_name + '/os_info.json'}")



