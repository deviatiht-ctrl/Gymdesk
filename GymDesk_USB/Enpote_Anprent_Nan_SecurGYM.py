#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Enpote_Anprent_Nan_SecurGYM.py
---------------------------------
Pran anprent manm ki pa ekspire yo ki sot nan BioStar (CSV: user_id, name, telefon, start, expiry, template0, template1)
epi mete yo nan SecurGYM:
  1. San doublon: matche pa telefòn (8 dènye chif) oswa pa non konplè.
  2. Pa ranplase anprent ki deja fèt nan SecurGYM: si moun nan gen anprent deja nan SecurGYM, nou KITE L.
  3. Si moun nan nan SecurGYM men li pa t gen anprent: nou ajoute anprent BioStar a pou li.
  4. Si moun nan pa t nan SecurGYM: nou kreye nouvo manm nan ak anprent li ak dat validite li.
  5. Remete tout anprent yo sou W2 a imedyatman.
"""

import sys
import os
import glob
import csv
import json
import uuid
import datetime
import urllib.request
import re

def normalize_phone(p):
    if not p:
        return ''
    digits = re.sub(r'\D', '', str(p))
    if len(digits) >= 8:
        return digits[-8:]
    return digits

def normalize_name(n):
    if not n:
        return ''
    clean = re.sub(r'\s+', ' ', str(n).strip().lower())
    return clean

def find_csv_file(arg_path=None):
    if arg_path and os.path.isfile(arg_path):
        return arg_path
    
    candidates = []
    # 1. Desktop
    desktop = os.path.join(os.path.expanduser('~'), 'Desktop')
    candidates.extend(glob.glob(os.path.join(desktop, 'BioStar_Anprent_*.csv')))
    # 2. GymDesk_USB
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates.extend(glob.glob(os.path.join(script_dir, 'BioStar_Anprent_*.csv')))
    candidates.extend(glob.glob(os.path.join(script_dir, '..', 'GymDesk_USB', 'BioStar_Anprent_*.csv')))
    
    if not candidates:
        return None
    candidates.sort(key=lambda x: os.path.getmtime(x), reverse=True)
    return candidates[0]

def find_sqlite_dbs():
    doc_dir = os.path.join(os.path.expanduser('~'), 'Documents')
    dbs = glob.glob(os.path.join(doc_dir, 'gymdesk_*_owner.sqlite'))
    if not dbs:
        dbs = glob.glob(os.path.join(doc_dir, 'gymdesk_*.sqlite'))
    return dbs

def main():
    print("=" * 65)
    print("  SecurGYM - Enpòtasyon Anprent BioStar 2 nan Baz Done a")
    print("=" * 65)
    
    csv_file = None
    if len(sys.argv) > 1:
        csv_file = find_csv_file(sys.argv[1])
    else:
        csv_file = find_csv_file()
        
    if not csv_file:
        print("\n[ATANSYON] Okenn fichye 'BioStar_Anprent_*.csv' pa jwenn.")
        print("Mete fichye CSV anprent BioStar a sou Desktop la oswa nan dosye sa a.")
        print("Egzanp: python Enpote_Anprent_Nan_SecurGYM.py C:\\Chemen\\BioStar_Anprent_xxx.csv\n")
        return 1
        
    print(f"\n[1/4] Lekti fichye CSV: {csv_file}")
    
    biostar_users = {}
    with open(csv_file, 'r', encoding='utf-8-sig', errors='ignore') as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = row.get('user_id', '').strip()
            name = row.get('name', '').strip()
            tel = normalize_phone(row.get('telefon') or row.get('phone') or uid)
            t0 = row.get('template0', '').strip()
            t1 = row.get('template1', '').strip()
            start = row.get('start_datetime', '').strip()
            exp = row.get('expiry_datetime', '').strip()
            
            if not t0:
                continue
                
            key = tel if tel else uid
            if key not in biostar_users:
                biostar_users[key] = {
                    'user_id': uid,
                    'name': name,
                    'phone': tel,
                    'start_datetime': start,
                    'expiry_datetime': exp,
                    'template0': t0,
                    'template1': t1,
                }
                
    print(f"  -> {len(biostar_users)} manm inik ak anprent valid nan fichye CSV a.")
    
    dbs = find_sqlite_dbs()
    if not dbs:
        print("[ERE] Baz done lokal SQLite SecurGYM pa jwenn nan Documents.")
        return 1
        
    import sqlite3
    
    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    for db_path in dbs:
        print(f"\n[2/4] Tretman baz done: {os.path.basename(db_path)}")
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        
        cur.execute("SELECT gym_id FROM records LIMIT 1")
        row_gym = cur.fetchone()
        if not row_gym:
            print("  [KITE] Baz done vid.")
            conn.close()
            continue
        gym_id = row_gym[0]
        
        cur.execute("SELECT payload FROM records WHERE entity = 'staff' AND deleted_at IS NULL LIMIT 1")
        staff_row = cur.fetchone()
        staff_id = json.loads(staff_row[0]).get('id') if staff_row else None
        
        cur.execute("SELECT payload FROM records WHERE entity = 'plans' AND deleted_at IS NULL LIMIT 1")
        plan_row = cur.fetchone()
        plan_id = json.loads(plan_row[0]).get('id') if plan_row else None
        
        cur.execute("SELECT id, payload FROM records WHERE entity = 'members' AND deleted_at IS NULL")
        existing_members = cur.fetchall()
        
        members_by_phone = {}
        members_by_name = {}
        for m_id, p_str in existing_members:
            p = json.loads(p_str)
            tel = normalize_phone(p.get('phone'))
            if tel:
                members_by_phone[tel] = (m_id, p)
            fname = p.get('first_name', '')
            lname = p.get('last_name', '')
            full1 = normalize_name(f"{fname} {lname}")
            full2 = normalize_name(f"{lname} {fname}")
            if full1:
                members_by_name[full1] = (m_id, p)
            if full2:
                members_by_name[full2] = (m_id, p)
                
        skipped_existing_fp = 0
        updated_added_fp = 0
        created_new_member = 0
        
        for b_key, b_user in biostar_users.items():
            b_tel = b_user['phone']
            b_name = normalize_name(b_user['name'])
            
            matched_id = None
            matched_payload = None
            
            if b_tel and b_tel in members_by_phone:
                matched_id, matched_payload = members_by_phone[b_tel]
            elif b_name and b_name in members_by_name:
                matched_id, matched_payload = members_by_name[b_name]
                
            if matched_payload:
                has_fp = bool(matched_payload.get('fingerprint_template') or matched_payload.get('fingerprint_backup_template'))
                if has_fp:
                    skipped_existing_fp += 1
                    continue
                else:
                    matched_payload['fingerprint_template'] = b_user['template0']
                    if b_user['template1']:
                        matched_payload['fingerprint_backup_template'] = b_user['template1']
                    matched_payload['fingerprint_registered'] = True
                    matched_payload['fingerprint_enrolled_at'] = now_iso
                    matched_payload['updated_at'] = now_iso
                    
                    new_p_str = json.dumps(matched_payload)
                    cur.execute("UPDATE records SET payload = ? WHERE entity = 'members' AND id = ?", (new_p_str, matched_id))
                    
                    outbox_id = str(uuid.uuid4())
                    cur.execute(
                        "INSERT INTO outbox (id, entity, entity_id, operation, payload, changed_at, created_at, status) "
                        "VALUES (?, 'members', ?, 'update', ?, ?, ?, 'pending')",
                        (outbox_id, matched_id, new_p_str, now_iso, now_iso)
                    )
                    updated_added_fp += 1
            else:
                new_id = str(uuid.uuid4())
                name_parts = b_user['name'].split(' ', 1)
                first_name = name_parts[0] if name_parts else 'Manm'
                last_name = name_parts[1] if len(name_parts) > 1 else ''
                
                member_num = b_user['phone'] if b_user['phone'] else b_user['user_id']
                if not member_num:
                    member_num = str(int(datetime.datetime.now().timestamp()))[-6:]
                    
                phone_formatted = f"+509{b_user['phone']}" if b_user['phone'] and len(b_user['phone']) == 8 else (b_user['phone'] or None)
                
                new_member = {
                    'id': new_id,
                    'gym_id': gym_id,
                    'first_name': first_name,
                    'last_name': last_name,
                    'phone': phone_formatted,
                    'email': None,
                    'notes': f"Enpòte sot BioStar 2 (ID: {b_user['user_id']})",
                    'status': 'active',
                    'member_number': member_num,
                    'fingerprint_registered': True,
                    'fingerprint_template': b_user['template0'],
                    'fingerprint_backup_template': b_user['template1'] if b_user['template1'] else None,
                    'fingerprint_enrolled_at': now_iso,
                    'access_status': 'active',
                    'created_by': staff_id,
                    'created_at': now_iso,
                    'updated_at': now_iso,
                    'deleted_at': None
                }
                
                new_p_str = json.dumps(new_member)
                cur.execute(
                    "INSERT INTO records (entity, id, gym_id, payload, server_version, deleted_at) "
                    "VALUES ('members', ?, ?, ?, NULL, NULL)",
                    (new_id, gym_id, new_p_str)
                )
                
                cur.execute(
                    "INSERT INTO outbox (id, entity, entity_id, operation, payload, changed_at, created_at, status) "
                    "VALUES (?, 'members', ?, 'insert', ?, ?, ?, 'pending')",
                    (str(uuid.uuid4()), new_id, new_p_str, now_iso, now_iso)
                )
                
                if plan_id:
                    sub_id = str(uuid.uuid4())
                    start_date = b_user['start_datetime'][:10] if b_user['start_datetime'] else now_iso[:10]
                    end_date = b_user['expiry_datetime'][:10] if b_user['expiry_datetime'] else '2030-12-31'
                    
                    sub = {
                        'id': sub_id,
                        'gym_id': gym_id,
                        'member_id': new_id,
                        'plan_id': plan_id,
                        'start_date': start_date,
                        'end_date': end_date,
                        'price': 0,
                        'status': 'active',
                        'created_by': staff_id,
                        'created_at': now_iso,
                        'updated_at': now_iso,
                        'deleted_at': None
                    }
                    sub_str = json.dumps(sub)
                    cur.execute(
                        "INSERT INTO records (entity, id, gym_id, payload, server_version, deleted_at) "
                        "VALUES ('subscriptions', ?, ?, ?, NULL, NULL)",
                        (sub_id, gym_id, sub_str)
                    )
                    cur.execute(
                        "INSERT INTO outbox (id, entity, entity_id, operation, payload, changed_at, created_at, status) "
                        "VALUES (?, 'subscriptions', ?, 'insert', ?, ?, ?, 'pending')",
                        (str(uuid.uuid4()), sub_id, sub_str, now_iso, now_iso)
                    )
                    
                created_new_member += 1
                if b_tel:
                    members_by_phone[b_tel] = (new_id, new_member)
                if b_name:
                    members_by_name[b_name] = (new_id, new_member)
                    
        cur.execute("DELETE FROM sync_metadata WHERE key LIKE 'terminal_sigs%'")
        conn.commit()
        conn.close()
        
        print(f"  -> {skipped_existing_fp} manm ki te gen anprent deja nan SecurGYM: KITE san touche.")
        print(f"  -> {updated_added_fp} manm ki te san anprent: anprent BioStar a ajoute pou yo.")
        print(f"  -> {created_new_member} nouvo manm kreye ak anprent yo san doublon.")
        
    print("\n[3/4] Fòse sinkronizasyon ak tèminal W2 a imedyatman...")
    try:
        req = urllib.request.Request('http://127.0.0.1:47811/health')
        with urllib.request.urlopen(req, timeout=2) as resp:
            data = json.loads(resp.read().decode())
            if data.get('status') == 'ok':
                print("  -> Ajan SecurGYM la sou liy.")
    except Exception:
        print("  -> Ajan SecurGYM poko louvri (l ap sinkronize otomatikman lè l demare).")

    print("\n[4/4] FINI AK SISÈ!")
    print("=" * 65)
    return 0

if __name__ == '__main__':
    sys.exit(main())
