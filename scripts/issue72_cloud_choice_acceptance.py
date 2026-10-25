#!/usr/bin/env python3
"""Issue 72 disposable cloud fixture, reusing Issue 71's guarded lifecycle.

Only the explicitly named isolated project can be mutated. Runtime credentials
remain in the protected Issue 72 control file and loopback fixture service.
"""
import builtins

import issue71_cloud_discovery_acceptance as core

core.PROJECT_STATE = core.ROOT / '.scratch/issue72/isolated-state.json'
core.PROJECT_NAME = 'Pacta issue72 disposable validation'
core.CONTROL_FILE = core.ROOT / '.dart_tool/issue72-cloud-control.json'
core.PORT = 30348

def fixture_print(*args, **kwargs):
    # Keep reused operator guidance accurate for this fixture's identity/port.
    values = [value.replace('Issue 71', 'Issue 72').replace('30347', str(core.PORT))
              if isinstance(value, str) else value for value in args]
    builtins.print(*values, **kwargs)


core.print = fixture_print
OriginalProject = core.AcceptanceProject


class ChoiceProject(OriginalProject):
    def seed_snapshot(self, user):
        super().seed_snapshot(user)
        self.management('/database/query', {'query':
            "update public.cloud_business_snapshots set data_updated_at='2001-01-01T00:00:00Z' "
            "where user_id='" + user['id'] + "';"})


core.AcceptanceProject = ChoiceProject

if __name__ == '__main__':
    core.main()
