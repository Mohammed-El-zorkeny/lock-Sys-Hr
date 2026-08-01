import os, sys

sys.stdout.reconfigure(encoding='utf-8')
filepath = r'c:\Users\Asus\Downloads\Hr\locksys_hr\lib\features\dailies\presentation\dailies_screen.dart'
lines = open(filepath, 'r', encoding='utf-8').readlines()

for idx, line in enumerate(lines):
    if 'DropdownButtonFormField' in line:
        # print 5 lines before and after
        print(f"--- Line {idx+1} ---")
        for i in range(max(0, idx-5), min(len(lines), idx+10)):
            print(f"{i+1}: {lines[i].strip()}")
