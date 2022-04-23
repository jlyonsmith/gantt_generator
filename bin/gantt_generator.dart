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
  final classes = [];
  final rows = [];
  final resourceColors = [
    '007FBE',
    '00B570',
    'FF9600',
  ];
  var startDate = DateFormat.yMd('en_US').parse(project['startDate']);

  if (startDate.getWeekday >= 6) {
    stderr.writeln(
        "Start date ${DateFormat.yMd().format(startDate)} is not a weekday");
    exitCode = -1;
    return;
  }

  final tasks = project['tasks'] as List<dynamic>;
  var taskIndex = 1;

  for (var task in tasks) {
    var taskClass = {};
    var taskRow = {};
    final className = "task-$taskIndex";
    final months = List.filled(12, {});

    months[startDate.month - 1] = {
      'itemStart': {'className': className}
    };
    taskRow['title'] = task['title'];
    taskRow['months'] = months;

    if (taskIndex == tasks.length) {
      taskRow['lastRow'] = true;
    }

    // Work out the offset % in the start month
    taskClass['name'] = className;
    taskClass['start'] = (startDate.day - 1) / startDate.getDaysInMonth;
    taskClass['color'] =
        resourceColors[(task['resource'] as double).toInt() - 1];

    // Calculate the duration % from start
    var date = startDate;
    var duration = (task['duration'] as double).toInt();
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
    taskClass['duration'] = max(durationPercent, 0.1);

    classes.add(taskClass);
    rows.add(taskRow);

    taskIndex++;
  }

  final data = {
    'title': project['title'],
    'cellWidth': 70,
    'classes': classes,
    'rows': rows,
  };
  //stdout.writeln(data);
  File(outputFilename).writeAsStringSync(htmlTemplate.renderString(data));

  stdout.writeln("Wrote Gantt chart to $outputFilename");
}
