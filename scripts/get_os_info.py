import argparse
import os

# Sigue siendo util para un cierre HTTP limpio (evita los errores SSL de aiohttp).
os.environ["DISABLE_AIOHTTP_TRANSPORT"] = "True"

import json
import subprocess
import shlex
import asyncio
from litellm import acompletion
from dotenv import load_dotenv

load_dotenv()

home = os.path.expanduser("~")
os_info_path = home + "/os_info/"
vm_list_path = home + "/vm_list.md"
vagrant_path = home + "/vagrant/"
vm_info_path = home + "/vm_info/"


async def generate_commands(vagrant_box, vm_name):
    prompt = f"""
            I am utilizing the following Vagrant box: https://portal.cloud.hashicorp.com/vagrant/discover/{vagrant_box}. 
            
            Provide the necessary commands to obtain the OS information. The commands should return the output in the terminal. The OS information should include details such as OS family, OS type, and OS version.
            
            If the Vagrant box is for an Android device, please provide the commands to retrieve the OS information from the Android device. If the Vagrant box is for a Windows machine, please provide the commands to retrieve the OS information from the Windows machine. If the Vagrant box is for a Linux machine, please provide the commands to retrieve the OS information from the Linux machine.

            IMPORTANT for Android: each command will already be executed inside the device shell via 'adb shell'. Therefore the commands must be the raw shell commands only (e.g. "getprop ro.build.version.release"), and must NOT start with "adb", "adb shell", or include any adb prefix.
            OUTPUT FORMAT:
            You must respond ONLY with a valid JSON object. Do not include explanations or markdown backticks.
            The JSON structure must be:
            {{
            "Commands": ["command1", "command2"]
            }}
            """

    response = await acompletion(
        model="groq/openai/gpt-oss-120b",
        fallbacks=["groq/openai/gpt-oss-20b"],
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
        try:
            data = json.load(f)
            commands = data.get("Commands", [])
        except json.JSONDecodeError:
            print(f"Error: commands.json for {vm_name} is not valid JSON. Skipping command execution.")
            commands = []
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
                result = subprocess.run(command_to_run, capture_output=True, text=True, timeout=15)
                command_outputs[command] = result.stdout

            except Exception as e:
                print(f"Error executing command '{command}': {e}")

    with open(os_info_path + vm_name + "/commands_execute.json", "w") as f:
        json.dump(command_outputs, f, indent=4)


async def get_os_info(vagrant_box, vm_name):
    with open(os_info_path + vm_name + "/commands_execute.json", "r") as f:
        command_outputs = json.load(f)

    with open(os_info_path + vm_name + "/commands.json", "r") as f:
        commands = json.load(f).get("Commands", [])

    try:
        with open(vm_list_path, "r") as f:
            vm_list = f.read()
    except FileNotFoundError:
        print(f"Error: {vm_list_path} file not found.")
        vm_list = ""

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

    response = await acompletion(
        model="groq/openai/gpt-oss-120b",
        fallbacks=["groq/openai/gpt-oss-20b"],
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

    # Edit vm_info file
    with open(vm_info_path + vm_name + ".json", "r+") as f:
        print(f)
        try:
            info = json.load(f)
            print(info)
            info["os_family"] = json_data.get("Os_Family", "")
            info["os_type"] = json_data.get("Os_Type", "")
            info["os_version"] = json_data.get("Os_Version","")
            if info.get("traffic_folder", "") == "":
                if "" not in [info["os_family"], info["os_type"], info["os_version"]]:
                    info["traffic_folder"] = "traffic/{}__{}__{}".format(info["os_family"], info["os_type"], info["os_version"])
                else:
                    info["traffic_folder"] = ""
            f.seek(0)
            json.dump(info, f, indent=4)
            f.truncate()
        except json.JSONDecodeError as e:
            print(e)


async def shutdown_litellm():
    try:
        from litellm.litellm_core_utils.logging_worker import GLOBAL_LOGGING_WORKER
        try:
            await asyncio.wait_for(GLOBAL_LOGGING_WORKER.flush(), timeout=5)
        except asyncio.TimeoutError:
            pass
        await GLOBAL_LOGGING_WORKER.stop()
    except Exception:
        pass
    await asyncio.sleep(0)


async def main(vagrant_box, vm_name):
    try:
        print(f"Getting OS info commands for virtual machine: {vm_name} with Vagrant box: {vagrant_box}")
        await generate_commands(vagrant_box, vm_name)
        print(f"Commands saved to {os_info_path + vm_name + '/commands.json'}")
        execute_commands(vagrant_box, vm_name)
        print(f"Command outputs saved to {os_info_path + vm_name + '/commands_execute.json'}")
        await get_os_info(vagrant_box, vm_name)
        print(f"OS information saved to {os_info_path + vm_name + '/os_info.json'} and {vm_info_path + vm_name + '.json'}")
    finally:
        await shutdown_litellm()


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

    asyncio.run(main(args.vagrant_box, args.vm_name))