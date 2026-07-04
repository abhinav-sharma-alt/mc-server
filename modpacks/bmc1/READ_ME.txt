YOU NEED JAVA 17 TO PLAY 1.19.2 MODPACKS. THIS CAN BE INSTALLED HERE https://adoptium.net/temurin/releases/?version=17 (install and run the .msi)
If your server still doesn't launch with Java 17, uninstall other Java versions!
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

ONLY USE THESE FILES TO RUN THE SERVER:
Windows = start.ps1
Linux = start.sh
(DO NOT USE THE .jar TO RUN THE SERVER!)

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Below is a list of commonly asked questions. If you have a question not answered in this document, please ask the question in our Discord: https://discord.gg/mcVsgB3AEh

	Q: How do I start the server?
A: Right click the Start.ps1 file and Open with Powershell. 
	Q: How do I join my server?
A: 1) Install the modpack using a modded launcher (Curseforge, GDLauncher, ATLauncher, etc)	2) go to the Multiplayer tab in the main menu	3) click Direct Connect and type localhost
	Q: How do others join my server?
A: They will connect using your Public IP Address, which can be found by typing "my ip address" into Google. If people are unable to join with this IP, find a portforwarding guide online.
	Q: How do I allocate more RAM?
A: 1) Double click the start.ps1 instead of opening with Powershell	2) Find the line that says $args and add your java arguments there. -Xmx8G will set your maximum memory usage to 8 gigabytes.
	Q: Should I be worried about errors in the console?
A: Unless there is something that is not working as expected, don't mind any errors. 99% of them mean nothing.

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
IMPORTANT FOR WINDOWS 11 22H2 USERS!:
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
	Q: When I open Powershell, it closes immediately! (This can also solve other issues!)
A: This is likely an issue with Powershell itself. Here is an alternative method of opening the start.ps1:
1) Press the Windows key, type Powershell and run as Administrator
2) Run the following: set-executionpolicy remotesigned
3) Agree by typing A
4) Run the start.ps1 again by Right click the Start.ps1 file and Open with Powershell.
5) Now it should work (If it does not work, restart your PC and try running again)
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

IF YOU DO NOT WANT TO FOLLOW THE ABOVE FIX THEN YOUR ONLY OPTION IS MANUAL INSTALLATION:

New Windows 11 22H2 Update causes the PowerShell not to work. I suggest these Videos for Manual Installation:
FORGE 1.19.2: https://www.youtube.com/watch?v=3HD0ibIpO-A
FABRIC: https://www.youtube.com/watch?v=b2W1Xb7nLKo
Make sure to Install the Server in our ServerPacks so it can use the correct files.