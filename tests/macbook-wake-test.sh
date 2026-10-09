#!/bin/sh
set -eu
python3 - "$HOME/scripts/macbook-wake" <<'PY'
import contextlib
import importlib.machinery
import importlib.util
import io
import os
import subprocess
import sys
import unittest
from unittest.mock import patch, Mock

loader = importlib.machinery.SourceFileLoader('wake', sys.argv.pop())
spec = importlib.util.spec_from_loader(loader.name, loader)
wake = importlib.util.module_from_spec(spec)
loader.exec_module(wake)
config_guard = wake.config_only

class WakeTest(unittest.TestCase):
    def setUp(self):
        guard = patch.object(wake, 'config_only', return_value=False)
        guard.start()
        self.addCleanup(guard.stop)

    def test_real_config_guard_accepts_both_option_positions_and_remote_quotes(self):
        for command, expected in (
            ('ssh -G macbook', True), ('ssh macbook -G', True),
            ('ssh -O check macbook', True), ('ssh macbook -O check', True),
            ("ssh macbook echo don't", False), ('ssh macbook echo -G', False),
            ('ssh -o BatchMode=yes macbook -vG', True),
        ):
            with self.subTest(command=command), patch.object(wake.subprocess, 'check_output', return_value=command):
                self.assertEqual(config_guard(), expected)

    def test_config_inspection_does_not_probe_or_wake(self):
        with patch.object(wake, 'config_only', return_value=True), patch.object(wake, 'reachable') as probe:
            self.assertEqual(wake.main(['host', '22']), 0)
            probe.assert_not_called()

    def test_reachable_does_not_send_wake(self):
        with patch.object(wake, 'reachable', return_value=True), patch.object(wake, 'send_wake') as send:
            self.assertEqual(wake.main(['host', '22']), 0)
            send.assert_not_called()

    def test_passive_check_never_sends_even_when_unreachable(self):
        with patch.object(wake, 'reachable', return_value=False), patch.object(wake, 'send_wake') as send:
            self.assertEqual(wake.main(['--check', 'host', '22']), 1)
            send.assert_not_called()

    def test_background_optout_does_not_even_probe(self):
        with patch.dict(os.environ, {'MACBOOK_NO_WAKE': '1'}), patch.object(wake, 'reachable') as probe:
            self.assertEqual(wake.main(['host', '22']), 0)
            probe.assert_not_called()

    def test_wakes_then_waits_for_connectivity(self):
        with patch.object(wake, 'reachable', side_effect=[False, False, True]), \
             patch.object(wake, 'home_network', return_value=('192.168.0.5', '192.168.0.255')), \
             patch.object(wake, 'send_wake') as send, patch.object(wake.time, 'sleep'), \
             patch.object(wake, 'settings', return_value={'macs': ['80:65:7c:c8:67:13']}):
            self.assertEqual(wake.main(['host', '22']), 0)
            self.assertEqual(send.call_count, 2)

    def test_other_network_fails_without_broadcast(self):
        with patch.object(wake, 'reachable', return_value=False), \
             patch.object(wake, 'settings', return_value={}), \
             patch.object(wake, 'home_network', side_effect=RuntimeError('not home')), \
             patch.object(wake, 'send_wake') as send:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(wake.main(['host', '22']), 1)
            send.assert_not_called()

    def test_failed_wake_is_bounded_and_explicit(self):
        with patch.object(wake, 'reachable', return_value=False), \
             patch.object(wake, 'home_network', return_value=('ip', 'broadcast')), \
             patch.object(wake, 'settings', return_value={}), \
             patch.object(wake, 'send_wake'), patch.object(wake.time, 'sleep'), \
             patch.object(wake.time, 'monotonic', side_effect=[0, 1, 31, 31]):
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                self.assertEqual(wake.main(['host', '22']), 1)
            self.assertIn('30 seconds', err.getvalue())

    def test_packet_contains_the_target_mac_sixteen_times(self):
        sock = Mock()
        with patch.object(wake.socket, 'socket') as create:
            create.return_value.__enter__.return_value = sock
            wake.send_wake(('192.168.0.5', '192.168.0.255'), {'macs': ['80:65:7c:c8:67:13']})
        packet = bytes.fromhex('ff' * 6 + '80657cc86713' * 16)
        self.assertEqual(sock.sendto.call_args_list[0].args, (packet, ('192.168.0.255', 9)))
        self.assertEqual(sock.sendto.call_count, 2)

unittest.main()
PY
