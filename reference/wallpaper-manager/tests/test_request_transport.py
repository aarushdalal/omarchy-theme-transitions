"""Large GUI request transport without writes to installed wallpapers."""
import io
import json
import unittest
from unittest.mock import patch

import wallpaper_manager as manager


class RequestTransportTests(unittest.TestCase):
    def call_main(self, arguments, stdin, execute):
        output = io.StringIO()
        with patch.object(manager.sys, 'argv', ['wallpaper_manager.py', *arguments]), \
                patch.object(manager.sys, 'stdin', io.StringIO(stdin)), \
                patch.object(manager.sys, 'stdout', output), \
                patch.object(manager.os, 'nice'), \
                patch.object(manager, 'execute', side_effect=execute):
            code = manager.main()
        return code, json.loads(output.getvalue())

    def test_large_queue_arrives_intact_through_stdin(self):
        request = {'action': 'queue-import', 'confirmed': True, 'batches': [
            {'group': 'Chosen group', 'target': 'both', 'items': [
                {'source': '/folder/' + 'long-folder-name/' * 15 + str(i) + '.png',
                 'title': 'Café — wallpaper ' + str(i)} for i in range(694)]}]}
        payload = json.dumps(request, ensure_ascii=False)
        self.assertGreater(len(payload.encode()), 131072)
        received = []
        def execute(value):
            received.append(value)
            return {'queued_job': 'isolated-test'}
        code, result = self.call_main(['--request', '-'], payload + '\n', execute)
        self.assertEqual(code, 0)
        self.assertTrue(result['ok'])
        self.assertEqual(received, [request])

    def test_existing_argument_requests_still_work(self):
        request = {'action': 'jobs'}
        code, result = self.call_main(['--request', json.dumps(request)], '',
                                      lambda value: {'jobs': []} if value == request else {})
        self.assertEqual(code, 0)
        self.assertEqual(result['jobs'], [])

    def test_malformed_stdin_returns_visible_error(self):
        def unexpected(value):
            self.fail('Invalid JSON must not reach an operation.')
        code, result = self.call_main(['--request', '-'], '{bad json}\n', unexpected)
        self.assertEqual(code, 1)
        self.assertFalse(result['ok'])
        self.assertTrue(result['message'])
