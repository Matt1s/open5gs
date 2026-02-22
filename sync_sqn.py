#!/usr/bin/env python3
"""
SQN Synchronization Script
Synchronizes Sequence Numbers (SQN) between Open5GS MongoDB and IMS HSS MySQL
"""

import sys
import subprocess
import argparse

class SQNSynchronizer:
    def __init__(self):
        # MySQL/IMS HSS Configuration
        self.mysql_container = "ims_mysql"
        self.mysql_user = "pyhss"
        self.mysql_pass = "ims_db_pass"
        self.mysql_db = "ims_hss_db"
        
        # MongoDB/Open5GS Configuration
        self.mongo_db = "open5gs"
        self.mongo_collection = "subscribers"
    
    def run_mysql_command(self, sql_command):
        """Execute MySQL command in container"""
        cmd = [
            'sudo', 'docker', 'exec', self.mysql_container,
            'mysql', '-u', self.mysql_user, f'-p{self.mysql_pass}',
            self.mysql_db, '-e', sql_command, '-sN'  # -sN for raw output without headers
        ]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return result.stdout.strip()
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
            return output.strip()
        except subprocess.CalledProcessError as e:
            raise Exception(f"MongoDB Error: {e.stderr}")
    
    def get_mongo_sqn(self, imsi):
        """Get SQN from MongoDB"""
        cmd = f"db.{self.mongo_collection}.findOne({{imsi: '{imsi}'}}, {{'security.sqn': 1}})"
        result = self.run_mongo_command(cmd)
        if result and 'null' not in result:
            # Parse the Long("value") format
            import re
            match = re.search(r'Long\("(\d+)"\)', result)
            if match:
                return int(match.group(1))
        return None
    
    def get_mysql_sqn(self, imsi):
        """Get SQN from MySQL"""
        sql = f"SELECT sqn FROM auc WHERE imsi = '{imsi}';"
        result = self.run_mysql_command(sql)
        if result:
            return int(result)
        return None
    
    def update_mongo_sqn(self, imsi, sqn):
        """Update SQN in MongoDB"""
        cmd = f'db.{self.mongo_collection}.updateOne({{imsi: "{imsi}"}}, {{$set: {{"security.sqn": NumberLong("{sqn}")}}}})'
        self.run_mongo_command(cmd)
    
    def update_mysql_sqn(self, imsi, sqn):
        """Update SQN in MySQL"""
        sql = f"UPDATE auc SET sqn = {sqn} WHERE imsi = '{imsi}';"
        self.run_mysql_command(sql)
    
    def check_imsi(self, imsi):
        """Check and display SQN values for an IMSI"""
        print(f"\n{'='*70}")
        print(f"Checking IMSI: {imsi}")
        print(f"{'='*70}")
        
        mongo_sqn = self.get_mongo_sqn(imsi)
        mysql_sqn = self.get_mysql_sqn(imsi)
        
        if mongo_sqn is None and mysql_sqn is None:
            print(f"❌ IMSI {imsi} not found in either database")
            return None, None
        
        print(f"\n📊 Current SQN Values:")
        print(f"   MongoDB (Open5GS):  {mongo_sqn if mongo_sqn is not None else 'NOT FOUND'}")
        print(f"   MySQL (IMS HSS):    {mysql_sqn if mysql_sqn is not None else 'NOT FOUND'}")
        
        if mongo_sqn is not None and mysql_sqn is not None:
            if mongo_sqn == mysql_sqn:
                print(f"\n✅ SQN values are synchronized ({mongo_sqn})")
            else:
                diff = abs(mongo_sqn - mysql_sqn)
                print(f"\n⚠️  SQN values are OUT OF SYNC (difference: {diff})")
                max_sqn = max(mongo_sqn, mysql_sqn)
                print(f"   Recommended action: Sync both to {max_sqn}")
        
        return mongo_sqn, mysql_sqn
    
    def sync_imsi(self, imsi, strategy='max', force_value=None):
        """Synchronize SQN for an IMSI"""
        mongo_sqn, mysql_sqn = self.check_imsi(imsi)
        
        if mongo_sqn is None and mysql_sqn is None:
            return False
        
        # Determine target SQN
        if force_value is not None:
            target_sqn = force_value
            print(f"\n🔧 Forcing SQN to: {target_sqn}")
        elif strategy == 'max':
            target_sqn = max(mongo_sqn or 0, mysql_sqn or 0)
            print(f"\n🔄 Using maximum SQN value: {target_sqn}")
        elif strategy == 'mongo':
            target_sqn = mongo_sqn
            print(f"\n🔄 Using MongoDB SQN value: {target_sqn}")
        elif strategy == 'mysql':
            target_sqn = mysql_sqn
            print(f"\n🔄 Using MySQL SQN value: {target_sqn}")
        else:
            print(f"❌ Unknown strategy: {strategy}")
            return False
        
        try:
            # Update both databases
            if mongo_sqn is not None and mongo_sqn != target_sqn:
                print(f"   Updating MongoDB: {mongo_sqn} → {target_sqn}")
                self.update_mongo_sqn(imsi, target_sqn)
            
            if mysql_sqn is not None and mysql_sqn != target_sqn:
                print(f"   Updating MySQL: {mysql_sqn} → {target_sqn}")
                self.update_mysql_sqn(imsi, target_sqn)
            
            print(f"\n✅ SQN synchronized successfully!")
            
            # Verify
            print(f"\n🔍 Verifying...")
            new_mongo_sqn = self.get_mongo_sqn(imsi)
            new_mysql_sqn = self.get_mysql_sqn(imsi)
            print(f"   MongoDB: {new_mongo_sqn}")
            print(f"   MySQL:   {new_mysql_sqn}")
            
            if new_mongo_sqn == new_mysql_sqn == target_sqn:
                print(f"   ✅ Verification successful!\n")
                return True
            else:
                print(f"   ⚠️  Verification failed - values don't match!\n")
                return False
                
        except Exception as e:
            print(f"\n❌ Error during synchronization: {str(e)}\n")
            return False
    
    def check_all(self):
        """Check SQN sync status for all IMSIs"""
        print(f"\n{'='*70}")
        print(f"Checking all IMSIs for SQN synchronization")
        print(f"{'='*70}\n")
        
        # Get all IMSIs from MongoDB
        cmd = f'db.{self.mongo_collection}.find({{}}, {{imsi: 1}}).toArray()'
        result = self.run_mongo_command(cmd)
        
        # Parse IMSIs (simplified - assumes format with imsi: 'value')
        import re
        imsis = re.findall(r"imsi:\s*'(\d+)'", result)
        
        if not imsis:
            print("No IMSIs found in MongoDB")
            return
        
        out_of_sync = []
        
        for imsi in imsis:
            mongo_sqn = self.get_mongo_sqn(imsi)
            mysql_sqn = self.get_mysql_sqn(imsi)
            
            status = "✅ SYNCED" if mongo_sqn == mysql_sqn else "⚠️  OUT OF SYNC"
            print(f"IMSI {imsi}:")
            print(f"  MongoDB: {mongo_sqn}, MySQL: {mysql_sqn} - {status}")
            
            if mongo_sqn != mysql_sqn:
                out_of_sync.append((imsi, mongo_sqn, mysql_sqn))
        
        if out_of_sync:
            print(f"\n⚠️  Found {len(out_of_sync)} IMSI(s) out of sync:")
            for imsi, mongo_sqn, mysql_sqn in out_of_sync:
                print(f"   {imsi}: MongoDB={mongo_sqn}, MySQL={mysql_sqn}")
            print(f"\nRun with 'sync-all' to synchronize all IMSIs")
        else:
            print(f"\n✅ All IMSIs are synchronized!")
        
        print()
    
    def sync_all(self, strategy='max'):
        """Synchronize SQN for all IMSIs"""
        print(f"\n{'='*70}")
        print(f"Synchronizing all IMSIs (strategy: {strategy})")
        print(f"{'='*70}\n")
        
        # Get all IMSIs from MongoDB
        cmd = f'db.{self.mongo_collection}.find({{}}, {{imsi: 1}}).toArray()'
        result = self.run_mongo_command(cmd)
        
        import re
        imsis = re.findall(r"imsi:\s*'(\d+)'", result)
        
        if not imsis:
            print("No IMSIs found in MongoDB")
            return
        
        success_count = 0
        fail_count = 0
        
        for imsi in imsis:
            print(f"\n{'─'*70}")
            if self.sync_imsi(imsi, strategy):
                success_count += 1
            else:
                fail_count += 1
        
        print(f"\n{'='*70}")
        print(f"Summary: {success_count} succeeded, {fail_count} failed")
        print(f"{'='*70}\n")

def main():
    parser = argparse.ArgumentParser(
        description='Synchronize SQN values between Open5GS MongoDB and IMS HSS MySQL',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Check SQN status for a specific IMSI
  %(prog)s check --imsi 262010000071630
  
  # Check all IMSIs
  %(prog)s check-all
  
  # Sync IMSI using maximum SQN value (default)
  %(prog)s sync --imsi 262010000071630
  
  # Sync IMSI using MongoDB value
  %(prog)s sync --imsi 262010000071630 --strategy mongo
  
  # Force SQN to specific value
  %(prog)s sync --imsi 262010000071630 --force 50000
  
  # Sync all IMSIs
  %(prog)s sync-all

Strategies:
  max   - Use the maximum SQN value from both databases (RECOMMENDED)
  mongo - Use the MongoDB value
  mysql - Use the MySQL value
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    # Check command
    check_parser = subparsers.add_parser('check', help='Check SQN sync status for an IMSI')
    check_parser.add_argument('--imsi', required=True, help='IMSI to check')
    
    # Check all command
    check_all_parser = subparsers.add_parser('check-all', help='Check SQN sync status for all IMSIs')
    
    # Sync command
    sync_parser = subparsers.add_parser('sync', help='Synchronize SQN for an IMSI')
    sync_parser.add_argument('--imsi', required=True, help='IMSI to synchronize')
    sync_parser.add_argument('--strategy', choices=['max', 'mongo', 'mysql'], 
                            default='max', help='Synchronization strategy (default: max)')
    sync_parser.add_argument('--force', type=int, help='Force SQN to specific value')
    
    # Sync all command
    sync_all_parser = subparsers.add_parser('sync-all', help='Synchronize SQN for all IMSIs')
    sync_all_parser.add_argument('--strategy', choices=['max', 'mongo', 'mysql'],
                                default='max', help='Synchronization strategy (default: max)')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    syncer = SQNSynchronizer()
    
    try:
        if args.command == 'check':
            syncer.check_imsi(args.imsi)
        elif args.command == 'check-all':
            syncer.check_all()
        elif args.command == 'sync':
            syncer.sync_imsi(args.imsi, args.strategy, args.force)
        elif args.command == 'sync-all':
            syncer.sync_all(args.strategy)
    except KeyboardInterrupt:
        print("\n\n⚠️  Operation cancelled by user.\n")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error: {str(e)}\n")
        sys.exit(1)

if __name__ == '__main__':
    main()
