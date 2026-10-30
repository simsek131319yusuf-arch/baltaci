import json,sys
d=json.load(open('data/upgrades.json',encoding='utf-8'))['upgrades']
tot=0
for u in d:
    c=sum(round(u['base_cost']*u['growth']**l) for l in range(u['max_level']))
    tot+=c
    print(u['id'],c)
print('total',tot)
