import argparse
import os

# Sigue siendo util para un cierre HTTP limpio (evita los errores SSL de aiohttp).
os.environ["DISABLE_AIOHTTP_TRANSPORT"] = "True"

import json
import subprocess
import asyncio
import paramiko
import winrm
from litellm import acompletion
from dotenv import load_dotenv

load_dotenv()

home = os.path.expanduser("~")
os_info_path = home + "/os_info/"
vm_list_path = home + "/vm_list.md"


def detect_family(vm_name):
    name_lc = vm_name.lower()
    if "windows" in name_lc:
        return "windows"
    if "android" in name_lc:
        return "android"
    return "other"


async def generate_commands(vm_name, family):

    prompt = f"""
            I have a virtual machine named '{vm_name}' running in VirtualBox.

            If the virtual machine is for an Android device, please provide the commands to retrieve the OS information from the Android device. If the virtual machine is for a Windows machine, please provide the commands to retrieve the OS information from the Windows machine. If the virtual machine is for a Linux machine, please provide the commands to retrieve the OS information from the Linux machine.

            Provide the necessary commands to obtain the OS information. The commands should return the output in the terminal. The OS information should include details such as OS family, OS type, and OS version.

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


def run_ssh_command(command, user, password, port):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(
            hostname="127.0.0.1",
            port=port,
            username=user,
            password=password,
            timeout=15,
            look_for_keys=False,
            allow_agent=False,
        )
        stdin, stdout, stderr = client.exec_command(command, timeout=15)
        return stdout.read().decode(errors="replace")
    finally:
        client.close()


def run_winrm_command(command, user, password, port):
    session = winrm.Session(
        f"http://127.0.0.1:{port}/wsman",
        auth=(user, password),
        transport="ntlm",
        server_cert_validation="ignore",
    )
    result = session.run_cmd(command)
    return result.std_out.decode(errors="replace")


def run_adb_command(command, adb_port):
    result = subprocess.run(
        ["adb", "-s", f"localhost:{adb_port}", "shell", command],
        capture_output=True,
        text=True,
    )
    return result.stdout


def execute_commands(vm_name, family, user, password, ssh_port, winrm_port, adb_port):
    with open(os_info_path + vm_name + "/commands.json", "r") as f:
        try:
            data = json.load(f)
            commands = data.get("Commands", [])
        except json.JSONDecodeError:
            print(f"Error: commands.json for {vm_name} is not valid JSON. Skipping command execution.")
            commands = []
        command_outputs = {}
        print(f"Executing commands for {vm_name}:")

        if family == "android":
            os.system(f"adb connect localhost:{adb_port}")

        for command in commands:
            try:
                if family == "android":
                    command_outputs[command] = run_adb_command(command, adb_port)
                elif family == "windows":
                    command_outputs[command] = run_winrm_command(command, user, password, winrm_port)
                else:
                    command_outputs[command] = run_ssh_command(command, user, password, ssh_port)
            except Exception as e:
                print(f"Error executing command '{command}': {e}")
                command_outputs[command] = ""

    with open(os_info_path + vm_name + "/commands_execute.json", "w") as f:
        json.dump(command_outputs, f, indent=4)


async def get_os_info(vm_name):
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


async def main(vm_name, family, user, password, ssh_port, winrm_port, adb_port):
    try:
        print(f"Getting OS info commands for virtual machine: {vm_name} (detected family: {family})")
        await generate_commands(vm_name, family)
        print(f"Commands saved to {os_info_path + vm_name + '/commands.json'}")
        execute_commands(vm_name, family, user, password, ssh_port, winrm_port, adb_port)
        print(f"Command outputs saved to {os_info_path + vm_name + '/commands_execute.json'}")
        await get_os_info(vm_name)
        print(f"OS information saved to {os_info_path + vm_name + '/os_info.json'}")
    finally:
        await shutdown_litellm()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Get OS information of a manually imported (OVA/VBOX/VDI) virtual machine."
    )
    parser.add_argument("-b", "--vm_name", type=str, required=True, help="Virtual machine name (example 'openbsd_7.2)")
    parser.add_argument("-u", "--user", type=str, default=None, help="Remote access username (not needed for Android)")
    parser.add_argument("-p", "--password", type=str, default=None, help="Remote access password (not needed for Android)")
    parser.add_argument("--ssh-port", type=int, help="Host port forwarded to guest")
    parser.add_argument("--winrm-port", type=int, help="Host port forwarded to guest WinRM")
    parser.add_argument("--adb-port", type=int, help="Host port forwarded to guest ADB")

    args = parser.parse_args()

    family = detect_family(args.vm_name)

    if family != "android" and (not args.user or not args.password):
        parser.error("--user and --password are required for non-Android guests")

    if family == "windows" and not args.winrm_port:
        parser.error("--winrm-port is required for Windows guests")
    elif family == "other" and not args.ssh_port:
        parser.error("--ssh-port is required for this guest")
    elif family == "android" and not args.adb_port:
        parser.error("--adb-port is required for Android guests")

    asyncio.run(main(args.vm_name, family, args.user, args.password, args.ssh_port, args.winrm_port, args.adb_port))
