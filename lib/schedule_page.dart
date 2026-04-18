import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'models/shift_model.dart';
import 'services/hive_service.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  @override
  void initState() {
    super.initState();
    // 监听 Hive Box 的变化
    Hive.box<ShiftModel>(HiveService.shiftsBoxName).listenable().addListener(_onBoxChanged);
  }

  @override
  void dispose() {
    Hive.box<ShiftModel>(HiveService.shiftsBoxName).listenable().removeListener(_onBoxChanged);
    super.dispose();
  }

  void _onBoxChanged() {
    setState(() {});
  }

  List<ShiftModel> get _shifts => HiveService.getAllShifts();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('班表'),
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: _shifts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.schedule,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无班表记录',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击右下角按钮添加班次',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _shifts.length,
              itemBuilder: (context, index) {
                final shift = _shifts[index];
                return _buildShiftCard(shift, index);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddShiftDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildShiftCard(ShiftModel shift, int index) {
    final dateFormat = DateFormat('yyyy年MM月dd日 EEEE', 'zh_CN');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showEditShiftDialog(shift, index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateFormat.format(shift.date),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _getShiftTypeColor(shift.shiftType),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                shift.shiftType,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.access_time,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_formatTimeOfDay(shift.startTime)} - ${_formatTimeOfDay(shift.endTime)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    icon: const Icon(Icons.more_vert),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('编辑'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('删除', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditShiftDialog(shift, index);
                      } else if (value == 'delete') {
                        _deleteShift(shift);
                      }
                    },
                  ),
                ],
              ),
              if (shift.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.note,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          shift.notes,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getShiftTypeColor(String shiftType) {
    switch (shiftType) {
      case '早班':
        return Colors.blue;
      case '中班':
        return Colors.orange;
      case '晚班':
        return Colors.purple;
      case '夜班':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _showAddShiftDialog() {
    _showShiftDialog();
  }

  void _showEditShiftDialog(ShiftModel shift, int index) {
    _showShiftDialog(shift: shift, index: index);
  }

  void _showShiftDialog({ShiftModel? shift, int? index}) {
    final dateController = TextEditingController(
      text: shift != null
          ? DateFormat('yyyy-MM-dd').format(shift.date)
          : DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    final shiftTypeController = TextEditingController(
      text: shift?.shiftType ?? '早班',
    );
    final startTimeController = TextEditingController(
      text: shift != null
          ? _formatTimeOfDay(shift.startTime)
          : '08:00',
    );
    final endTimeController = TextEditingController(
      text: shift != null ? _formatTimeOfDay(shift.endTime) : '16:00',
    );
    final notesController = TextEditingController(
      text: shift?.notes ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(shift == null ? '添加班次' : '编辑班次'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: dateController,
                      decoration: const InputDecoration(
                        labelText: '日期',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      readOnly: true,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: shift?.date ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                          locale: const Locale('zh', 'CN'),
                        );
                        if (picked != null) {
                          dateController.text =
                              DateFormat('yyyy-MM-dd').format(picked);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: shiftTypeController.text,
                      decoration: const InputDecoration(
                        labelText: '班次类型',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.work),
                      ),
                      items: const [
                        DropdownMenuItem(value: '早班', child: Text('早班')),
                        DropdownMenuItem(value: '中班', child: Text('中班')),
                        DropdownMenuItem(value: '晚班', child: Text('晚班')),
                        DropdownMenuItem(value: '夜班', child: Text('夜班')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          shiftTypeController.text = value;
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: startTimeController,
                            decoration: const InputDecoration(
                              labelText: '开始时间',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.access_time),
                            ),
                            readOnly: true,
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: shift?.startTime ??
                                    const TimeOfDay(hour: 8, minute: 0),
                              );
                              if (time != null) {
                                startTimeController.text =
                                    _formatTimeOfDay(time);
                                setDialogState(() {});
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: endTimeController,
                            decoration: const InputDecoration(
                              labelText: '结束时间',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.access_time),
                            ),
                            readOnly: true,
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: shift?.endTime ??
                                    const TimeOfDay(hour: 16, minute: 0),
                              );
                              if (time != null) {
                                endTimeController.text = _formatTimeOfDay(time);
                                setDialogState(() {});
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: '备注',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final date = DateFormat('yyyy-MM-dd')
                        .parse(dateController.text);
                    final startTimeParts = startTimeController.text.split(':');
                    final endTimeParts = endTimeController.text.split(':');
                    final startTime = TimeOfDay(
                      hour: int.parse(startTimeParts[0]),
                      minute: int.parse(startTimeParts[1]),
                    );
                    final endTime = TimeOfDay(
                      hour: int.parse(endTimeParts[0]),
                      minute: int.parse(endTimeParts[1]),
                    );

                    final newShift = ShiftModel.fromTimeOfDay(
                      date: date,
                      shiftType: shiftTypeController.text,
                      startTime: startTime,
                      endTime: endTime,
                      notes: notesController.text,
                    );

                    if (index != null && shift != null) {
                      final boxIndex = HiveService.getShiftIndex(shift);
                      if (boxIndex != null) {
                        final updatedShift = ShiftModel(
                          date: date,
                          shiftType: shiftTypeController.text,
                          startHour: startTime.hour,
                          startMinute: startTime.minute,
                          endHour: endTime.hour,
                          endMinute: endTime.minute,
                          notes: notesController.text,
                          id: shift.id,
                        );
                        await HiveService.updateShift(boxIndex, updatedShift);
                      }
                    } else {
                      await HiveService.addShift(newShift);
                    }

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: Text(shift == null ? '添加' : '保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteShift(ShiftModel shift) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: const Text('确定要删除这个班次吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (shift.id != null) {
                  await HiveService.deleteShiftById(shift.id!);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }
}
