"""Failed-only retries preserve settings, successes, drafts and history."""
from pathlib import Path
import json
import unittest
from unittest.mock import patch
from PIL import Image
import test_importer as fixture
import wallpaper_add as core
import wallpaper_jobs as jobs
import wallpaper_manager as manager


class RetryJobsTests(unittest.TestCase):
    setUp = fixture.ImporterTests.setUp
    tearDown = fixture.ImporterTests.tearDown
    fake_run = fixture.ImporterTests.fake_run

    def failed_job(self, replace=False):
        self.missing = self.base / 'missing.png'
        request = {'confirmed': True, 'batches': [
            {'label': 'First folder', 'group': 'Bleach', 'target': 'omarchy', 'items': [{'source': str(self.source), 'title': 'Success'}]},
            {'label': 'Second folder', 'group': 'JJK', 'target': 'daemon-os', 'mode': 'static',
             'allow_static_scenes': True, 'replace': replace,
             'items': [{'source': str(self.missing), 'title': 'Retry me'}]}]}
        with patch.object(jobs.subprocess, 'Popen'):
            submitted = jobs.submit(request)
        self.job_id = submitted['queued_job']; self.directory = jobs.root() / self.job_id
        with patch.object(jobs.subprocess, 'run'):
            jobs.run_job(self.directory)
        self.assertEqual(core.read_json(self.directory / 'status.json')['failed'], 1)
        return request

    def repair_source(self):
        Image.new('RGB', (32, 18), '#445566').save(self.missing)

    def test_retry_includes_only_failures_and_preserves_every_batch_option(self):
        self.failed_job(); self.repair_source()
        original = core.read_json(self.directory / 'request.json')['batches']
        successful_image = core.Locations().themes / 'success/backgrounds/success.png'
        successful_hash = core.digest(successful_image)
        unrelated = [dict(original[0], label='My separate queue')]
        jobs.save_draft(unrelated)
        preview = manager.execute({'action': 'retry-preview', 'id': self.job_id})['retry_preview']
        self.assertEqual(preview['count'], 1)
        self.assertEqual(preview['batches'], [original[1]])
        with patch.object(jobs.subprocess, 'Popen'):
            result = manager.execute({'action': 'retry-failed', 'id': self.job_id, 'confirmed': True})
        child = jobs.root() / result['queued_job']
        self.assertEqual(core.read_json(child / 'request.json')['batches'], [original[1]])
        self.assertEqual(core.read_json(child / 'status.json')['retry_of'], self.job_id)
        self.assertEqual(jobs.load_draft()['draft_batches'], unrelated)
        with patch.object(jobs.subprocess, 'run'):
            jobs.run_job(child)
        state = core.read_json(child / 'status.json')
        self.assertEqual((state['done'], state['failed']), (1, 0))
        self.assertEqual(core.digest(successful_image), successful_hash)
        self.assertEqual(core.read_json(self.directory / 'status.json')['failed'], 1)
        self.assertEqual(jobs.load_draft()['draft_batches'], unrelated)

    def test_requires_confirmation_and_refuses_invalid_ids(self):
        self.failed_job()
        with self.assertRaisesRegex(core.ImportFailure, 'confirm'):
            jobs.retry_failed(self.job_id)
        for value in ['', '..', '../outside', '/tmp/outside']:
            with self.subTest(value=value), self.assertRaises(core.ImportFailure):
                jobs.retry_preview(value)

    def test_running_or_pending_original_cannot_be_retried(self):
        self.failed_job()
        state = core.read_json(self.directory / 'status.json')
        state.update(state='pending')
        jobs.atomic(self.directory / 'status.json', state)
        with self.assertRaisesRegex(core.ImportFailure, 'finish'):
            jobs.retry_preview(self.job_id)

    def test_successful_retry_is_not_repeated_even_with_replace_enabled(self):
        self.failed_job(replace=True); self.repair_source()
        with patch.object(jobs.subprocess, 'Popen'):
            result = jobs.retry_failed(self.job_id, True)
        with patch.object(jobs.subprocess, 'run'):
            jobs.run_job(jobs.root() / result['queued_job'])
        preview = jobs.retry_preview(self.job_id)['retry_preview']
        self.assertEqual((preview['count'], preview['skipped']), (0, 1))
        with patch.object(jobs.subprocess, 'Popen') as spawn:
            result = jobs.retry_failed(self.job_id, True)
        self.assertTrue(result['retry_empty']); spawn.assert_not_called()

    def test_independently_recovered_files_are_skipped(self):
        self.failed_job(); self.repair_source()
        manager.execute({'action': 'import', 'confirmed': True, 'target': 'daemon-os',
                         'items': [{'source': str(self.missing), 'title': 'Retry me', 'group': 'JJK'}]})
        preview = jobs.retry_preview(self.job_id)['retry_preview']
        self.assertEqual((preview['count'], preview['skipped']), (0, 1))

    def test_an_active_retry_cannot_be_queued_twice(self):
        self.failed_job()
        with patch.object(jobs.subprocess, 'Popen') as spawn:
            jobs.retry_failed(self.job_id, True)
            with self.assertRaisesRegex(core.ImportFailure, 'already queued or running'):
                jobs.retry_failed(self.job_id, True)
        self.assertEqual(spawn.call_count, 1)

    def test_recovered_source_moved_to_another_drive_is_recognized_by_hash(self):
        self.failed_job(); self.repair_source()
        original = self.base / 'old-drive.png'; original.write_bytes(self.missing.read_bytes())
        manager.execute({'action': 'import', 'confirmed': True, 'target': 'daemon-os',
                         'items': [{'source': str(original), 'title': 'Retry me', 'group': 'JJK'}]})
        self.assertEqual(jobs.retry_preview(self.job_id)['retry_preview']['count'], 0)
        self.missing.write_bytes(b'different source contents')
        self.assertEqual(jobs.retry_preview(self.job_id)['retry_preview']['count'], 1)

    def test_retry_preflight_failure_keeps_unrelated_draft(self):
        request = self.failed_job(); jobs.save_draft([request['batches'][0]])
        with patch.object(core, 'check_backup_coverage', side_effect=core.ImportFailure('Missing backup coverage')), \
                patch.object(jobs.subprocess, 'Popen') as spawn:
            with self.assertRaisesRegex(core.ImportFailure, 'coverage'):
                jobs.retry_failed(self.job_id, True)
        spawn.assert_not_called()
        self.assertEqual(jobs.load_draft()['draft_batches'], [request['batches'][0]])

    def test_active_retry_blocks_overlapping_retry_of_an_older_child(self):
        self.failed_job()
        with patch.object(jobs.subprocess, 'Popen'):
            first_retry = jobs.retry_failed(self.job_id, True)['queued_job']
        with patch.object(jobs.subprocess, 'run'):
            jobs.run_job(jobs.root() / first_retry)  # The source is still missing.
        with patch.object(jobs.subprocess, 'Popen'):
            jobs.retry_failed(self.job_id, True)
        with self.assertRaisesRegex(core.ImportFailure, 'already queued or running'):
            jobs.retry_failed(first_retry, True)

    def test_interrupted_run_retries_unfinished_items_only(self):
        self.failed_job()
        lines = (self.directory / 'events.jsonl').read_text().splitlines()
        (self.directory / 'events.jsonl').write_text(lines[0] + '\n' + '{partial')
        state = core.read_json(self.directory / 'status.json'); state.update(state='interrupted', failed=0, completed=1)
        jobs.atomic(self.directory / 'status.json', state)
        preview = jobs.retry_preview(self.job_id)['retry_preview']
        self.assertEqual(preview['count'], 1)
        self.assertEqual(preview['batches'][0]['items'][0]['title'], 'Retry me')
