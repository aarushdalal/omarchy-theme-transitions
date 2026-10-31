"""Durable imports with independent folder groups and per-item failure continuation."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from PIL import Image
import test_importer as fixture
import wallpaper_add as core
import wallpaper_manager as manager
import wallpaper_jobs as jobs
import wallpaper_groups as groups

ROOT = Path(__file__).resolve().parents[1]

class BackgroundJobsTests(unittest.TestCase):
    setUp = fixture.ImporterTests.setUp
    tearDown = fixture.ImporterTests.tearDown
    fake_run = fixture.ImporterTests.fake_run

    def request(self):
        second=self.base/'second.png';Image.new('RGB',(32,18),'#445566').save(second)
        return {'action':'queue-import','confirmed':True,'batches':[
            {'label':'Folder A','group':'Bleach','target':'omarchy','items':[{'source':str(self.source),'title':'First'}]},
            {'label':'Folder B','group':'JJK','target':'daemon-os','items':[{'source':str(second),'title':'Second'}]}]}

    def test_requires_confirmation_and_refuses_duplicate_sources(self):
        request=self.request();request['confirmed']=False
        with self.assertRaises(core.ImportFailure):jobs.validate(request)
        request['confirmed']=True;request['batches'][1]['items'][0]['source']=str(self.source)
        with self.assertRaises(core.ImportFailure):jobs.validate(request)
        self.assertFalse(jobs.root().exists())

    def test_preflight_rejects_uncovered_library_before_spawning_and_keeps_draft(self):
        paths=core.Locations();config=paths.config/'omarchy/cloud-sync.json'
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({'folders':[
            {'enabled':True,'type':'directory','path':str(self.project)},
            {'enabled':True,'type':'directory','path':str(paths.config)}]}))
        manifest=config.parent/'manifests/DAEMONOS_BACKUP_MANIFEST.json'
        manifest.parent.mkdir();manifest.write_text('{}');manifest.with_suffix('.md').write_text('# Backup\n')
        request=self.request()
        with patch.object(jobs.subprocess,'Popen') as spawn,patch.object(manager,'execute') as execute:
            with self.assertRaisesRegex(core.ImportFailure,'coverage is missing'):
                jobs.submit(request)
        spawn.assert_not_called();execute.assert_not_called()
        self.assertFalse(jobs.root().exists())
        self.assertEqual(jobs.load_draft()['draft_batches'],jobs.validate(request))

    def test_draft_round_trip_keeps_folder_groups_options_and_can_clear(self):
        batches=self.request()['batches']
        manager.execute({'action':'draft-save','batches':batches})
        self.assertEqual(manager.execute({'action':'draft-load'})['draft_batches'],batches)
        manager.execute({'action':'draft-save','batches':[]})
        self.assertEqual(manager.execute({'action':'draft-load'})['draft_batches'],[])

    def test_submit_checks_video_destination_when_needed(self):
        request=self.request();request['batches'][0]['mode']='video'
        with patch.object(core,'check_backup_coverage') as coverage,patch.object(jobs.subprocess,'Popen'):
            jobs.submit(request)
        self.assertIn(core.Locations().videos/'__import_check__',coverage.call_args.args[1])

    def test_background_folder_batches_keep_separate_groups_and_targets(self):
        with patch.object(jobs.subprocess,'Popen') as spawn:
            result=jobs.submit(self.request())
        self.assertTrue(spawn.call_args.kwargs['start_new_session'])
        directory=jobs.root()/result['queued_job']
        self.assertEqual(jobs.list_jobs()[0]['state'],'pending')
        with patch.object(jobs.subprocess,'run'):
            jobs.run_job(directory)
        state=core.read_json(directory/'status.json')
        self.assertEqual((state['state'],state['done'],state['failed']),('completed',2,0))
        self.assertEqual(groups.group_for('first'),'Bleach');self.assertEqual(groups.group_for('second'),'JJK')
        records=core.read_json(core.Locations().registry)['wallpapers']
        self.assertEqual(records['first']['targets'],['omarchy'])
        self.assertEqual(records['second']['targets'],['daemon-os'])

    def test_missing_file_does_not_block_later_batch(self):
        request=self.request();request['batches'][0]['items'][0]['source']=str(self.base/'missing.png')
        with patch.object(jobs.subprocess,'Popen'):result=jobs.submit(request)
        directory=jobs.root()/result['queued_job']
        with patch.object(jobs.subprocess,'run'):jobs.run_job(directory)
        state=core.read_json(directory/'status.json')
        self.assertEqual((state['state'],state['done'],state['failed']),('completed-with-errors',1,1))
        self.assertEqual(state['completed'],2)
        self.assertEqual(groups.group_for('second'),'JJK')
        self.assertEqual(len((directory/'events.jsonl').read_text().splitlines()),2)

    def test_waits_for_another_import_instead_of_failing_the_batch(self):
        with patch.object(jobs.subprocess,'Popen'):result=jobs.submit(self.request())
        directory=jobs.root()/result['queued_job'];original=manager.execute;calls=[]
        def busy_once(request):
            calls.append(request)
            if len(calls)==1:raise core.ImportFailure('Another wallpaper import is running. Try again after it finishes.')
            return original(request)
        with patch.object(manager,'execute',side_effect=busy_once),patch.object(jobs.time,'sleep') as wait,patch.object(jobs.subprocess,'run'):
            jobs.run_job(directory)
        wait.assert_called_once_with(0.5)
        state=core.read_json(directory/'status.json')
        self.assertEqual((state['done'],state['failed']),(2,0))

    def test_shell_reopen_can_read_progress_and_details(self):
        with patch.object(jobs.subprocess,'Popen'):result=manager.execute(self.request())
        data=manager.execute({'action':'jobs'})
        self.assertEqual(data['jobs'][0]['id'],result['queued_job'])
        self.assertIn('Queued',manager.execute({'action':'job-details','id':result['queued_job']})['job_details'])
        for value in ['..','../outside','']:
            with self.assertRaises(core.ImportFailure):manager.execute({'action':'job-details','id':value})

class DetachedWorkerTests(unittest.TestCase):
    def test_actual_detached_worker_finishes_after_submitter_exits(self):
        with tempfile.TemporaryDirectory(prefix='wallpaper-background-check-') as temp:
            base=Path(temp);home=base/'home';home.mkdir();project=base/'project';project.mkdir()
            bin_dir=base/'bin';bin_dir.mkdir()
            aether=bin_dir/'aether'
            aether.write_text('''#!/usr/bin/python3
import sys,time
from pathlib import Path
time.sleep(0.3)
out=Path(sys.argv[sys.argv.index('--output')+1]);out.mkdir(parents=True,exist_ok=True)
values={'background':'#101020','foreground':'#eeeeee','accent':'#6699cc'}
values.update({f'color{i}':'#223344' for i in range(16)})
(out/'colors.toml').write_text('\\n'.join(f'{k} = "{v}"' for k,v in values.items())+'\\n')
''');aether.chmod(0o755)
            notify=bin_dir/'notify-send';notify.write_text('#!/bin/sh\nexit 0\n');notify.chmod(0o755)
            source=base/'one.png';Image.new('RGB',(64,36),'#334455').save(source)
            request={'confirmed':True,'batches':[{'group':'Chosen group','target':'omarchy','items':[{'source':str(source),'title':'Detached One'}]}]}
            request_file=base/'input.json';request_file.write_text(json.dumps(request))
            env=dict(os.environ,HOME=str(home),XDG_CONFIG_HOME=str(home/'.config'),XDG_DATA_HOME=str(home/'.local/share'),XDG_STATE_HOME=str(home/'.local/state'),PATH=str(bin_dir)+os.pathsep+os.environ['PATH'],PYTHONPATH=str(ROOT))
            command='import json,sys;from pathlib import Path;import wallpaper_add as c;import wallpaper_jobs as j;c.PROJECT=Path(sys.argv[1]);print(json.dumps(j.submit(json.loads(Path(sys.argv[2]).read_text()))))'
            submitted=subprocess.run([sys.executable,'-c',command,str(project),str(request_file)],env=env,text=True,capture_output=True,check=True,timeout=5)
            job_id=json.loads(submitted.stdout)['queued_job'];status=project/'data/jobs'/job_id/'status.json'
            deadline=time.monotonic()+15
            while time.monotonic()<deadline:
                state=json.loads(status.read_text())
                if state['state'] not in {'pending','running'}:break
                time.sleep(.1)
            self.assertEqual(state['state'],'completed',state)
            self.assertTrue((home/'.config/omarchy/themes/detached-one/backgrounds/detached-one.png').is_file())
            self.assertEqual(json.loads((home/'.config/omarchy/theme-groups.json').read_text())['assignments']['detached-one'],'Chosen group')
            self.assertEqual(submitted.returncode,0)
