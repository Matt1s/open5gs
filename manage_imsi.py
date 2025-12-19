#!/usr/bin/env python3
"""
IMSI Management Script for Open5GS WebUI and IMS HSS Databases
Manages subscriber data across both MongoDB (Open5GS) and MySQL (IMS HSS)
"""

import sys
import argparse
import subprocess
import json
from datetime import datetime

class IMSIManager:
    def __init__(self):
        # MySQL/IMS HSS Configuration
        self.mysql_container = "ims_mysql"
        self.mysql_user = "pyhss"
        self.mysql_pass = "ims_db_pass"
        self.mysql_db = "ims_hss_db"
        
        # MongoDB/Open5GS Configuration
        self.mongo_db = "open5gs"
        self.mongo_collection = "subscribers"
        
        # Default settings based on reference IMSIs (262010000071627, 262010000071630)
        # Using predefined ObjectIds from the reference configuration
        self.default_settings = {
            'open5gs': {
                'ambr': {
                    'downlink': {'value': 1, 'unit': 3},
                    'uplink': {'value': 1, 'unit': 3}
                },
                'schema_version': 1,
                'access_restriction_data': 32,
                'subscriber_status': 0,
                'network_access_mode': 0,
                'subscribed_rau_tau_timer': 12,
                'security': {
                    'amf': '8000',
                    'op': None,
                    'sqn': 0
                },
                'slice': [{
                    '_id': '6532e2849472b5658ce22b3a',  # Predefined slice ID
                    'sst': 1,
                    'default_indicator': True,
                    'session': [
                        {
                            '_id': '6532e2849472b5658ce22b3b',  # Predefined internet session ID
                            'name': 'internet',
                            'type': 1,
                            'qos': {
                                'index': 9,
                                'arp': {
                                    'priority_level': 8,
                                    'pre_emption_capability': 1,
                                    'pre_emption_vulnerability': 1
                                }
                            },
                            'ambr': {
                                'downlink': {'value': 1, 'unit': 3},
                                'uplink': {'value': 1, 'unit': 3}
                            },
                            'pcc_rule': []
                        },
                        {
                            '_id': '6532e2849472b5658ce22b3c',  # Predefined IMS session ID
                            'name': 'ims',
                            'type': 1,
                            'qos': {
                                'index': 5,
                                'arp': {
                                    'priority_level': 1,
                                    'pre_emption_capability': 1,
                                    'pre_emption_vulnerability': 1
                                }
                            },
                            'ambr': {
                                'downlink': {'value': 3850, 'unit': 1},
                                'uplink': {'value': 1530, 'unit': 1}
                            },
                            'pcc_rule': [{
                                '_id': 'NEW_OBJECTID',  # Will be replaced with new ObjectId
                                'qos': {
                                    'arp': {
                                        'priority_level': 2,
                                        'pre_emption_capability': 2,
                                        'pre_emption_vulnerability': 2
                                    },
                                    'mbr': {
                                        'downlink': {'value': 128, 'unit': 1},
                                        'uplink': {'value': 128, 'unit': 1}
                                    },
                                    'gbr': {
                                        'downlink': {'value': 128, 'unit': 1},
                                        'uplink': {'value': 128, 'unit': 1}
                                    },
                                    'index': 1
                                },
                                'flow': []
                            }]
                        }
                    ]
                }]
            },
            'ims_hss': {
                'amf': '8000',
                'sqn': 0,
                'ifc_path': 'default_ifc.xml',
                'pcscf_realm': 'ims.mnc001.mcc262.3gppnetwork.org',
                'scscf': 'sip:scscf.ims.mnc001.mcc262.3gppnetwork.org:6060',
                'scscf_realm': 'ims.mnc001.mcc262.3gppnetwork.org',
                'realm': 'ims.mnc001.mcc262.3gppnetwork.org',
                # subscriber table settings
                'enabled': 1,
                'default_apn': 1,  # References apn_id=1 (ims)
                'apn_list': '1',
                'ue_ambr_dl': 256000,
                'ue_ambr_ul': 256000,
                'nam': 0,
                'roaming_enabled': 1
            }
        }

    def run_mysql_command(self, sql_command):
        """Execute MySQL command in container"""
        cmd = [
            'sudo', 'docker', 'exec', self.mysql_container,
            'mysql', '-u', self.mysql_user, f'-p{self.mysql_pass}',
            self.mysql_db, '-e', sql_command
        ]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return result.stdout
        except subprocess.CalledProcessError as e:
            raise Exception(f"MySQL Error: {e.stderr}")

    def run_mongo_command(self, command):
        """Execute MongoDB command"""
        cmd = ['mongosh', self.mongo_db, '--quiet', '--eval', command]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            # Filter out warnings
            output = '\n'.join([line for line in result.stdout.split('\n') 
                               if not line.startswith('Warning:') and 
                               not 'history will not be persisted' in line])
            return output
        except subprocess.CalledProcessError as e:
            raise Exception(f"MongoDB Error: {e.stderr}")

    def generate_objectid(self):
        """Generate a new MongoDB ObjectId"""
        import random
        import time
        
        # MongoDB ObjectId structure: 4-byte timestamp + 5-byte random + 3-byte counter
        timestamp = int(time.time())
        random_part = ''.join([f'{random.randint(0,255):02x}' for _ in range(5)])
        counter = random.randint(0, 0xffffff)
        
        return f"{timestamp:08x}{random_part}{counter:06x}"

    def check_imsi_exists_mongo(self, imsi):
        """Check if IMSI exists in MongoDB"""
        command = f"db.{self.mongo_collection}.findOne({{imsi: '{imsi}'}}) ? true : false"
        result = self.run_mongo_command(command)
        return 'true' in result.lower()

    def check_imsi_exists_mysql(self, imsi, table):
        """Check if IMSI exists in MySQL table"""
        sql = f"SELECT COUNT(*) as count FROM {table} WHERE imsi = '{imsi}';"
        result = self.run_mysql_command(sql)
        # Parse result (skip header line)
        lines = result.strip().split('\n')
        if len(lines) > 1:
            count = int(lines[1])
            return count > 0
        return False

    def get_auc_id(self, imsi):
        """Get auc_id for a given IMSI"""
        sql = f"SELECT auc_id FROM auc WHERE imsi = '{imsi}';"
        result = self.run_mysql_command(sql)
        lines = result.strip().split('\n')
        if len(lines) > 1:
            return int(lines[1])
        return None

    def add_imsi(self, imsi, msisdn, ki, opc):
        """Add IMSI to both databases"""
        print(f"\n{'='*60}")
        print(f"Adding IMSI: {imsi}")
        print(f"MSISDN: {msisdn}")
        print(f"{'='*60}\n")

        # Check if IMSI already exists
        mongo_exists = self.check_imsi_exists_mongo(imsi)
        mysql_auc_exists = self.check_imsi_exists_mysql(imsi, 'auc')
        mysql_ims_exists = self.check_imsi_exists_mysql(imsi, 'ims_subscriber')
        mysql_subscriber_exists = self.check_imsi_exists_mysql(imsi, 'subscriber')

        if mongo_exists or mysql_auc_exists or mysql_ims_exists or mysql_subscriber_exists:
            print(f"⚠️  WARNING: IMSI {imsi} already exists in one or more databases:")
            if mongo_exists:
                print(f"   - Open5GS MongoDB")
            if mysql_auc_exists:
                print(f"   - IMS HSS AUC table")
            if mysql_ims_exists:
                print(f"   - IMS HSS ims_subscriber table")
            if mysql_subscriber_exists:
                print(f"   - IMS HSS subscriber table")
            response = input("\nDo you want to overwrite? (yes/no): ")
            if response.lower() != 'yes':
                print("❌ Operation cancelled.")
                return False

            # Delete existing entries
            print("\n🗑️  Removing existing entries...")
            self.delete_imsi(imsi, silent=True)

        try:
            # 1. Add to Open5GS MongoDB
            print("📝 Adding to Open5GS MongoDB...")
            settings = self.default_settings['open5gs']
            
            # Generate new ObjectId for pcc_rule
            pcc_rule_oid = self.generate_objectid()
            
            # Build document using mongosh with proper ObjectId syntax
            mongo_cmd = f"""
            db.{self.mongo_collection}.insertOne({{
                imsi: '{imsi}',
                msisdn: ['{msisdn}'],
                security: {{
                    k: '{ki.upper()}',
                    amf: '{settings['security']['amf']}',
                    op: null,
                    opc: '{opc.upper()}',
                    sqn: NumberLong({settings['security']['sqn']})
                }},
                ambr: {{
                    downlink: {{ value: {settings['ambr']['downlink']['value']}, unit: {settings['ambr']['downlink']['unit']} }},
                    uplink: {{ value: {settings['ambr']['uplink']['value']}, unit: {settings['ambr']['uplink']['unit']} }}
                }},
                schema_version: {settings['schema_version']},
                access_restriction_data: {settings['access_restriction_data']},
                subscriber_status: {settings['subscriber_status']},
                network_access_mode: {settings['network_access_mode']},
                subscribed_rau_tau_timer: {settings['subscribed_rau_tau_timer']},
                slice: [{{
                    _id: ObjectId('{settings['slice'][0]['_id']}'),
                    sst: {settings['slice'][0]['sst']},
                    default_indicator: true,
                    session: [
                        {{
                            _id: ObjectId('{settings['slice'][0]['session'][0]['_id']}'),
                            name: '{settings['slice'][0]['session'][0]['name']}',
                            type: {settings['slice'][0]['session'][0]['type']},
                            qos: {{
                                index: {settings['slice'][0]['session'][0]['qos']['index']},
                                arp: {{
                                    priority_level: {settings['slice'][0]['session'][0]['qos']['arp']['priority_level']},
                                    pre_emption_capability: {settings['slice'][0]['session'][0]['qos']['arp']['pre_emption_capability']},
                                    pre_emption_vulnerability: {settings['slice'][0]['session'][0]['qos']['arp']['pre_emption_vulnerability']}
                                }}
                            }},
                            ambr: {{
                                downlink: {{ value: {settings['slice'][0]['session'][0]['ambr']['downlink']['value']}, unit: {settings['slice'][0]['session'][0]['ambr']['downlink']['unit']} }},
                                uplink: {{ value: {settings['slice'][0]['session'][0]['ambr']['uplink']['value']}, unit: {settings['slice'][0]['session'][0]['ambr']['uplink']['unit']} }}
                            }},
                            pcc_rule: []
                        }},
                        {{
                            _id: ObjectId('{settings['slice'][0]['session'][1]['_id']}'),
                            name: '{settings['slice'][0]['session'][1]['name']}',
                            type: {settings['slice'][0]['session'][1]['type']},
                            qos: {{
                                index: {settings['slice'][0]['session'][1]['qos']['index']},
                                arp: {{
                                    priority_level: {settings['slice'][0]['session'][1]['qos']['arp']['priority_level']},
                                    pre_emption_capability: {settings['slice'][0]['session'][1]['qos']['arp']['pre_emption_capability']},
                                    pre_emption_vulnerability: {settings['slice'][0]['session'][1]['qos']['arp']['pre_emption_vulnerability']}
                                }}
                            }},
                            ambr: {{
                                downlink: {{ value: {settings['slice'][0]['session'][1]['ambr']['downlink']['value']}, unit: {settings['slice'][0]['session'][1]['ambr']['downlink']['unit']} }},
                                uplink: {{ value: {settings['slice'][0]['session'][1]['ambr']['uplink']['value']}, unit: {settings['slice'][0]['session'][1]['ambr']['uplink']['unit']} }}
                            }},
                            pcc_rule: [{{
                                _id: ObjectId('{pcc_rule_oid}'),
                                qos: {{
                                    arp: {{
                                        priority_level: 2,
                                        pre_emption_capability: 2,
                                        pre_emption_vulnerability: 2
                                    }},
                                    mbr: {{
                                        downlink: {{ value: 128, unit: 1 }},
                                        uplink: {{ value: 128, unit: 1 }}
                                    }},
                                    gbr: {{
                                        downlink: {{ value: 128, unit: 1 }},
                                        uplink: {{ value: 128, unit: 1 }}
                                    }},
                                    index: 1
                                }},
                                flow: []
                            }}]
                        }}
                    ]
                }}],
                mme_host: [],
                mme_realm: [],
                purge_flag: [],
                __v: 0
            }})
            """
            self.run_mongo_command(mongo_cmd)
            print("   ✅ Open5GS MongoDB - Success")

            # 2. Add to IMS HSS AUC table
            print("📝 Adding to IMS HSS AUC table...")
            ims_settings = self.default_settings['ims_hss']
            timestamp = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
            
            sql_auc = f"""
            INSERT INTO auc (ki, opc, amf, sqn, imsi, last_modified)
            VALUES ('{ki.upper()}', '{opc.upper()}', '{ims_settings['amf']}', 
                    {ims_settings['sqn']}, '{imsi}', '{timestamp}');
            """
            self.run_mysql_command(sql_auc)
            print("   ✅ IMS HSS AUC table - Success")

            # Get the auc_id that was just created
            auc_id = self.get_auc_id(imsi)
            if not auc_id:
                raise Exception("Failed to retrieve auc_id after insertion")

            # 3. Add to IMS HSS subscriber table (references auc_id)
            print("📝 Adding to IMS HSS subscriber table...")
            
            sql_subscriber = f"""
            INSERT INTO subscriber 
            (imsi, enabled, auc_id, default_apn, apn_list, msisdn, 
             ue_ambr_dl, ue_ambr_ul, nam, roaming_enabled)
            VALUES ('{imsi}', {ims_settings['enabled']}, {auc_id}, 
                    {ims_settings['default_apn']}, '{ims_settings['apn_list']}', 
                    '{msisdn}', {ims_settings['ue_ambr_dl']}, 
                    {ims_settings['ue_ambr_ul']}, {ims_settings['nam']}, 
                    {ims_settings['roaming_enabled']});
            """
            self.run_mysql_command(sql_subscriber)
            print("   ✅ IMS HSS subscriber table - Success")

            # 4. Add to IMS HSS ims_subscriber table
            print("📝 Adding to IMS HSS ims_subscriber table...")
            
            sql_ims = f"""
            INSERT INTO ims_subscriber 
            (msisdn, imsi, ifc_path, pcscf_realm, scscf, scscf_realm)
            VALUES ('{msisdn}', '{imsi}', '{ims_settings['ifc_path']}', 
                    '{ims_settings['pcscf_realm']}', '{ims_settings['scscf']}', 
                    '{ims_settings['scscf_realm']}');
            """
            self.run_mysql_command(sql_ims)
            print("   ✅ IMS HSS ims_subscriber table - Success")

            print(f"\n✅ Successfully added IMSI {imsi} to all databases!\n")
            return True

        except Exception as e:
            print(f"\n❌ Error adding IMSI: {str(e)}")
            print("⚠️  Rolling back changes...")
            self.delete_imsi(imsi, silent=True)
            return False

    def delete_imsi(self, imsi, silent=False):
        """Delete IMSI from both databases"""
        if not silent:
            print(f"\n{'='*60}")
            print(f"Deleting IMSI: {imsi}")
            print(f"{'='*60}\n")

        try:
            # 1. Delete from Open5GS MongoDB
            if not silent:
                print("🗑️  Deleting from Open5GS MongoDB...")
            mongo_cmd = f"db.{self.mongo_collection}.deleteOne({{imsi: '{imsi}'}})"
            self.run_mongo_command(mongo_cmd)
            if not silent:
                print("   ✅ Open5GS MongoDB - Deleted")

            # 2. Delete from IMS HSS subscriber table (must be before auc due to FK)
            if not silent:
                print("🗑️  Deleting from IMS HSS subscriber table...")
            sql_subscriber = f"DELETE FROM subscriber WHERE imsi = '{imsi}';"
            self.run_mysql_command(sql_subscriber)
            if not silent:
                print("   ✅ IMS HSS subscriber table - Deleted")

            # 3. Delete from IMS HSS ims_subscriber table
            if not silent:
                print("🗑️  Deleting from IMS HSS ims_subscriber table...")
            sql_ims = f"DELETE FROM ims_subscriber WHERE imsi = '{imsi}';"
            self.run_mysql_command(sql_ims)
            if not silent:
                print("   ✅ IMS HSS ims_subscriber table - Deleted")

            # 4. Delete from IMS HSS AUC table (must be last due to FK)
            if not silent:
                print("🗑️  Deleting from IMS HSS AUC table...")
            sql_auc = f"DELETE FROM auc WHERE imsi = '{imsi}';"
            self.run_mysql_command(sql_auc)
            if not silent:
                print("   ✅ IMS HSS AUC table - Deleted")

            if not silent:
                print(f"\n✅ Successfully deleted IMSI {imsi} from all databases!\n")
            return True

        except Exception as e:
            if not silent:
                print(f"\n❌ Error deleting IMSI: {str(e)}\n")
            return False

    def query_imsi(self, imsi):
        """Query IMSI from both databases"""
        print(f"\n{'='*60}")
        print(f"Querying IMSI: {imsi}")
        print(f"{'='*60}\n")

        try:
            # Query Open5GS MongoDB
            print("📊 Open5GS MongoDB:")
            mongo_cmd = f"db.{self.mongo_collection}.findOne({{imsi: '{imsi}'}})"
            result = self.run_mongo_command(mongo_cmd)
            if result and result.strip() and 'null' not in result.lower():
                print(result)
            else:
                print("   ❌ Not found")

            # Query IMS HSS AUC table
            print("\n📊 IMS HSS AUC table:")
            sql_auc = f"SELECT * FROM auc WHERE imsi = '{imsi}'\\G"
            result = self.run_mysql_command(sql_auc)
            if result and len(result.strip().split('\n')) > 1:
                print(result)
            else:
                print("   ❌ Not found")

            # Query IMS HSS subscriber table
            print("\n📊 IMS HSS subscriber table:")
            sql_subscriber = f"SELECT * FROM subscriber WHERE imsi = '{imsi}'\\G"
            result = self.run_mysql_command(sql_subscriber)
            if result and len(result.strip().split('\n')) > 1:
                print(result)
            else:
                print("   ❌ Not found")

            # Query IMS HSS ims_subscriber table
            print("\n📊 IMS HSS ims_subscriber table:")
            sql_ims = f"SELECT * FROM ims_subscriber WHERE imsi = '{imsi}'\\G"
            result = self.run_mysql_command(sql_ims)
            if result and len(result.strip().split('\n')) > 1:
                print(result)
            else:
                print("   ❌ Not found")

            print()

        except Exception as e:
            print(f"\n❌ Error querying IMSI: {str(e)}\n")

def main():
    parser = argparse.ArgumentParser(
        description='Manage IMSIs in Open5GS WebUI and IMS HSS databases',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Add a new IMSI
  %(prog)s add --imsi 262010000071631 --msisdn 1234567892 \\
      --ki 4A8EF5F361EE8359BEF1CB1F27A1F0C2 \\
      --opc 7433B4B73FD7C612E42EDEF1FA71F7FB

  # Delete an IMSI
  %(prog)s delete --imsi 262010000071631

  # Query an IMSI
  %(prog)s query --imsi 262010000071627

Note: Script uses settings from reference IMSIs:
  - 262010000071627
  - 262010000071630
  - Realm: ims.mnc001.mcc262.3gppnetwork.org (MCC=262, MNC=01)
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    # Add command
    add_parser = subparsers.add_parser('add', help='Add a new IMSI')
    add_parser.add_argument('--imsi', required=True, help='IMSI (e.g., 262010000071631)')
    add_parser.add_argument('--msisdn', required=True, help='MSISDN/Phone number (e.g., 1234567892)')
    add_parser.add_argument('--ki', required=True, help='Ki key (32 hex characters)')
    add_parser.add_argument('--opc', required=True, help='OPC key (32 hex characters)')
    
    # Delete command
    delete_parser = subparsers.add_parser('delete', help='Delete an IMSI')
    delete_parser.add_argument('--imsi', required=True, help='IMSI to delete')
    
    # Query command
    query_parser = subparsers.add_parser('query', help='Query an IMSI')
    query_parser.add_argument('--imsi', required=True, help='IMSI to query')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    # Validate inputs
    if args.command in ['add', 'delete', 'query']:
        if len(args.imsi) < 14 or len(args.imsi) > 15:
            print("❌ Error: IMSI must be 14-15 digits")
            sys.exit(1)
        if not args.imsi.isdigit():
            print("❌ Error: IMSI must contain only digits")
            sys.exit(1)
    
    if args.command == 'add':
        if len(args.ki) != 32:
            print("❌ Error: Ki must be exactly 32 hex characters")
            sys.exit(1)
        if len(args.opc) != 32:
            print("❌ Error: OPC must be exactly 32 hex characters")
            sys.exit(1)
        try:
            int(args.ki, 16)
            int(args.opc, 16)
        except ValueError:
            print("❌ Error: Ki and OPC must be valid hexadecimal strings")
            sys.exit(1)
    
    # Execute command
    manager = IMSIManager()
    
    try:
        if args.command == 'add':
            success = manager.add_imsi(args.imsi, args.msisdn, args.ki, args.opc)
            sys.exit(0 if success else 1)
        elif args.command == 'delete':
            success = manager.delete_imsi(args.imsi)
            sys.exit(0 if success else 1)
        elif args.command == 'query':
            manager.query_imsi(args.imsi)
            sys.exit(0)
    except KeyboardInterrupt:
        print("\n\n⚠️  Operation cancelled by user.\n")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {str(e)}\n")
        sys.exit(1)

if __name__ == '__main__':
    main()
