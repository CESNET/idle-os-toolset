import os
import glob
import json

pattern = "/data/virtual_machines/vm_info/*.json"
paths = glob.glob(pattern)

for path in paths:
    print(path)
    with open(path, "r+") as f:
        data = json.load(f)

        if data.get("traffic_folder", "") == "":
            os_family = data.get("os_family", "")
            os_type = data.get("os_type", "")
            os_version = data.get("os_version", "")
            if "" in [os_family, os_type, os_version]:
                print("Could not update traffic folder, missing information.")
                continue
            data["traffic_folder"] = "traffic/{}__{}__{}".format(os_family, os_type, os_version)
            print(data["traffic_folder"])

        f.seek(0)
        json.dump(data, f, indent=4)
        f.truncate()
    print("*"*50)
