#!/usr/bin/env python3

from rich.console import Console

console = Console()

while True:
console.print("\n[bold cyan]Infinity Host Backup Tool[/bold cyan]")
console.print("[1] Setup Backup")
console.print("[2] Modify Backup")
console.print("[3] View Status")
console.print("[4] Exit")

```
choice = input("\nSelect Option: ").strip()

if choice == "1":
    console.print("\nSelect Backup Provider")
    console.print("[1] Google Drive")
    console.print("[2] MEGA")

    provider = input("Choice: ").strip()

    backup_name = input("Backup Name: ").strip()
    backup_path = input("Folder Path: ").strip()
    interval = input("Backup Interval (Hours): ").strip()

    new_file = input("Create New Backup File Every Time? (y/n): ").strip()

    console.print("\nConfiguration Saved")
    console.print(f"Provider: {provider}")
    console.print(f"Name: {backup_name}")
    console.print(f"Path: {backup_path}")
    console.print(f"Interval: {interval} Hours")
    console.print(f"New File: {new_file}")

elif choice == "2":
    console.print("Modify Backup (Coming Soon)")

elif choice == "3":
    console.print("Status (Coming Soon)")

elif choice == "4":
    break

else:
    console.print("[red]Invalid Option[/red]")
```
