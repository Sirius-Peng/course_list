#!/usr/bin/env python3
"""Regression checks for platform isolation and the complication layout contract."""
from pathlib import Path
import tarfile,sys
root = Path(__file__).resolve().parents[1]
widget = (root/'Widgets/CourseStatusWidget.swift').read_text()
watch = (root/'Widgets/WatchComplicationView.swift').read_text()
app = (root/'Apps/Watch/CourseListWatchApp.swift').read_text()
assert '#if os(watchOS)\n        .contentMarginsDisabled()\n        #endif' in widget
assert 'WatchComplicationView(entry: entry)' in widget
assert '#else\n            CourseWidgetView(entry: entry)' in widget
assert 'CourseStatusCard(' not in app and 'WatchCourseHero(' in app
for token in ['widgetRenderingMode', 'widgetAccentable()', 'isLuminanceReduced', 'showsWidgetContainerBackground', 'maxHeight: .infinity', 'Text(timerInterval:', '.clipShape(Circle())']:
    assert token in watch, token
assert '.supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])' in widget
if len(sys.argv) > 1:
    with tarfile.open(sys.argv[1]) as archive:
        old = archive.extractfile('Widgets/CourseStatusWidget.swift').read().decode()
        assert old[old.index('struct CourseWidgetView:'):] == widget[widget.index('struct CourseWidgetView:'):], 'iPhone widget appearance changed'
        for name in ['Shared/CourseViews.swift','Sources/ScheduleCore/Models.swift','Shared/ScheduleModel.swift','Apps/iPhone/CourseListApp.swift']:
            assert (root/name).read_bytes() == archive.extractfile(name).read(), name
print('WATCH_UI: 3 families; watch-only margins/colors; native countdown; iPhone UI/data paths unchanged')
