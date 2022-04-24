import 'package:args/args.dart';
import 'package:resource_portable/resource.dart' show Resource;
import 'package:json5/json5.dart';
import 'package:mustache_template/mustache.dart';
import 'package:intl/intl.dart';
import 'package:dart_date/dart_date.dart';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math';

void main(List<String> arguments) async {
  final ArgParser argParser = ArgParser()
    ..addOption('input',
        abbr: 'i',
        defaultsTo: 'project.json5',
        help: "Input file name. (Default: project.json5)")
    ..addOption('output',
        abbr: 'o',
        defaultsTo: 'index.html',
        help: "Output file name. (Default: index.html)")
    ..addFlag('help',
        abbr: 'h', negatable: false, help: "Displays this help information.");
  final argResults = argParser.parse(arguments);

  if (argResults['help']) {
    print("""
${argParser.usage}
    """);
    return;
  }

  final inputFilename = argResults['input'];
  final project = JSON5.parse(File(inputFilename).readAsStringSync());

  stdout.writeln("Read project file $inputFilename");

  final resource = Resource("package:gantt_generator/template/index.html");
  final htmlSource = await resource.readAsString(encoding: utf8);
  final outputFilename = argResults['output'];
  final htmlTemplate =
      Template(htmlSource, name: outputFilename, lenient: true);
  final taskClasses = [];
  final milestoneClasses = [];
  final rows = [];
  final colors = [
    '007FBE',
    '00B570',
    'FF9600',
    '000000',
  ];
  var startDate = DateFormat.yMd('en_US').parse(project['startDate']);

  if (startDate.getWeekday >= 6) {
    stderr.writeln(
        "Start date ${DateFormat.yMd().format(startDate)} is not a weekday");
    exitCode = -1;
    return;
  }

  final items = project['items'] as List<dynamic>;
  var id = 1;

  for (var item in items) {
    var rowClass = {};
    var taskRow = {};
    final months = List.filled(12, {});

    taskRow['months'] = months;
    taskRow['title'] = item['title'];

    if (id == items.length) {
      taskRow['lastRow'] = true;
    }

    rowClass['color'] = colors[(item['color'] as double).toInt() - 1];

    // Work out the offset % in the start month
    rowClass['start'] = (startDate.day - 1) / startDate.getDaysInMonth;

    if (item['duration'] == null) {
      final className = "milestone-$id";

      // This is a milestone
      months[startDate.month - 1] = {
        'milestone': {'className': className},
      };

      rowClass['name'] = className;

      milestoneClasses.add(rowClass);
    } else {
      final className = "task-$id";

      rowClass['name'] = className;

      // This is a task
      months[startDate.month - 1] = {
        'bar': {'className': className}
      };

      // Calculate the duration % from start
      var date = startDate;
      var duration = (item['duration'] as double).toInt();
      // Move forward a day a time until the duration is reached
      while (duration > 0) {
        if (date.getWeekday >= 6) {
          // Skip weekends
          date += Duration(days: 1);
          continue;
        }

        duration--;
        date += Duration(days: 1);
      }

      double durationPercent;

      if (date.month == startDate.month) {
        // If still in same month, duration is percent of days in month
        durationPercent =
            Interval(startDate, date).duration.inDays / date.getDaysInMonth;
      } else {
        // Add remainder of first month
        durationPercent = (startDate.getDaysInMonth - startDate.day + 1) /
            startDate.getDaysInMonth;

        // Add offset of day in last month
        durationPercent += (date.day - 1) / date.getDaysInMonth;

        // Add 100% for other months
        durationPercent += date.month - startDate.month - 1;
      }

      startDate = date;

      // Ensure minimum percentage duration
      rowClass['duration'] = max(durationPercent, 0.1);

      taskClasses.add(rowClass);
    }

    rows.add(taskRow);

    id++;
  }

  final data = {
    'title': project['title'],
    'cellWidth': 70,
    'milestoneClasses': milestoneClasses,
    'taskClasses': taskClasses,
    'rows': rows,
  };
  //stdout.writeln(data);
  File(outputFilename).writeAsStringSync(htmlTemplate.renderString(data));

  stdout.writeln("Wrote Gantt chart to $outputFilename");
}
