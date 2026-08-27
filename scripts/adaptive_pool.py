#!/usr/bin/env python3
import argparse, csv, ipaddress, math, re
from collections import defaultdict
from datetime import date

COLO_COUNTRY = {
    **dict.fromkeys("NRT KIX FUK OKA".split(), "JP"), **dict.fromkeys("SIN".split(), "SG"),
    **dict.fromkeys("HKG".split(), "HK"), **dict.fromkeys("ICN".split(), "KR"),
    **dict.fromkeys("TPE KHH".split(), "TW"), **dict.fromkeys("MNL CEB".split(), "PH"),
    **dict.fromkeys("SGN HAN".split(), "VN"), **dict.fromkeys("KUL PEN".split(), "MY"),
    **dict.fromkeys("ALA NQZ".split(), "KZ"), **dict.fromkeys("ULN".split(), "MN"),
    **dict.fromkeys("DUB".split(), "IE"), **dict.fromkeys("FRA TXL BER MUC DUS HAM".split(), "DE"),
    **dict.fromkeys("LHR MAN EDI".split(), "GB"), **dict.fromkeys("AMS".split(), "NL"),
    **dict.fromkeys("MXP FCO".split(), "IT"),
    **dict.fromkeys("LAX SJC SEA PDX PHX DEN DFW ORD ATL MIA IAD EWR JFK BOS".split(), "US"),
}

def country_from_remark(value):
    m = re.search(r"\b([A-Za-z]{2})\b", value or "")
    return m.group(1).upper() if m else ""

def normalize_country(colo, remark):
    return COLO_COUNTRY.get((colo or "").strip().upper(), country_from_remark(remark))

def parse_pairs(text, default=1):
    out = defaultdict(lambda: default)
    for item in re.split(r"[,\s]+", text or ""):
        if "=" in item:
            key, value = item.split("=", 1)
            if value.isdigit(): out[key.upper()] = max(1, int(value))
    return out

def generate(args):
    seeds=[]
    with open(args.previous_nodes, encoding="ascii", newline="") as f:
        for row in csv.reader(f):
            if len(row)>=3: seeds.append((row[0], int(row[1]), row[2].upper()))
    if args.gslege and __import__('pathlib').Path(args.gslege).exists():
        with open(args.gslege, encoding="ascii", newline="") as f:
            for row in csv.reader(f):
                if len(row)>=2: seeds.append((row[0],443,row[1].upper()))
    multipliers=parse_pairs(args.multipliers)
    prefixes=defaultdict(list)
    for ip,port,country in seeds:
        try: net=ipaddress.ip_network(f"{ip}/24", strict=False)
        except ValueError: continue
        key=(country,port)
        limit=args.max_prefixes*multipliers[country]
        if str(net) not in prefixes[key] and len(prefixes[key])<limit: prefixes[key].append(str(net))
    rotation=date.today().timetuple().tm_yday
    with open(args.hot_output,"w",encoding="ascii",newline="") as f:
        w=csv.writer(f,lineterminator="\n")
        for (country,port),nets in sorted(prefixes.items()):
            count=min(254,args.samples*multipliers[country])
            for net_text in nets:
                net=ipaddress.ip_network(net_text)
                for i in range(count):
                    host=1+((rotation+math.floor(i*254/count))%254)
                    w.writerow((str(net.network_address+host),port,country))
    ports=[int(x) for x in args.ports.split(',') if x.strip()]
    cidrs=[ipaddress.ip_network(x.strip()) for x in args.ct_cidrs.split(',') if x.strip()]
    ips=[]; seen=set()
    for net in cidrs:
        usable=net.num_addresses-2 if net.num_addresses>2 else net.num_addresses
        for i in range(args.ct_samples):
            off=(1+((rotation+math.floor(i*usable/args.ct_samples))%usable)) if net.num_addresses>2 else ((rotation+i)%net.num_addresses)
            ip=str(net.network_address+off)
            if ip not in seen: seen.add(ip); ips.append(ip)
    with open(args.ct_output,"w",encoding="ascii",newline="") as f:
        w=csv.writer(f,lineterminator="\n")
        for port in ports:
            for ip in ips: w.writerow((ip,port,"CT-SEED"))

def row_obj(row, current):
    country=normalize_country(row[2] if len(row)>2 else "", row[3] if len(row)>3 else "")
    return {"row":row,"country":country,"key":(row[0],row[1]),"speed":float(row[9] or 0),"latency":float(row[8] or 999),"current":current}

def rolling(args):
    def load(path,current):
        with open(path,encoding="utf-8-sig",newline="") as f:
            reader=csv.reader(f); header=next(reader); return header,[row_obj(r,current) for r in reader if len(r)>=10]
    header,old=load(args.previous,False); _,cur=load(args.current,True)
    cur_by=defaultdict(list)
    for x in cur: cur_by[x["country"]].append(x)
    selected=[]
    for country in sorted(cur_by):
        c=sorted(cur_by[country],key=lambda x:(-x["speed"],x["latency"]))
        chosen=c[:args.max_per_city]
        selected.extend(chosen)
    with open(args.output,"w",encoding="utf-8",newline="") as f:
        w=csv.writer(f,lineterminator="\n"); w.writerow(header)
        grouped=defaultdict(list)
        for x in selected: grouped[x["country"]].append(x)
        for country in sorted(grouped):
            for idx,x in enumerate(sorted(grouped[country],key=lambda y:(y["latency"],-y["speed"])),1):
                row=x["row"][:]; row[3]=f"{country} [{args.location}#{idx:02d} {x['speed']:.1f}MB/s]"; w.writerow(row)
    print(f"previous={len(old)} current={len(cur)} output={len(selected)}")

def main():
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest="cmd",required=True)
    g=sub.add_parser("generate");
    for name in ("previous_nodes","gslege","ports","ct_cidrs","hot_output","ct_output","multipliers"): g.add_argument(f"--{name.replace('_','-')}",required=True)
    g.add_argument("--samples",type=int,default=4); g.add_argument("--max-prefixes",type=int,default=4); g.add_argument("--ct-samples",type=int,default=32); g.set_defaults(func=generate)
    r=sub.add_parser("rolling");
    for name in ("previous","current","output","location"): r.add_argument(f"--{name}",required=True)
    r.add_argument("--max-per-city",type=int,default=20); r.add_argument("--replace-fraction",type=float,default=.2); r.set_defaults(func=rolling)
    a=p.parse_args(); a.func(a)
if __name__=="__main__": main()
