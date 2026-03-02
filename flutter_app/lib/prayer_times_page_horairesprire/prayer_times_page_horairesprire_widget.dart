import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'prayer_times_page_horairesprire_model.dart';
export 'prayer_times_page_horairesprire_model.dart';

class PrayerTimesPageHorairesprireWidget extends StatefulWidget {
  const PrayerTimesPageHorairesprireWidget({super.key});

  static String routeName = 'PrayerTimesPageHorairesprire';
  static String routePath = '/prayerTimesPageHorairesprire';

  @override
  State<PrayerTimesPageHorairesprireWidget> createState() =>
      _PrayerTimesPageHorairesprireWidgetState();
}

class _PrayerTimesPageHorairesprireWidgetState
    extends State<PrayerTimesPageHorairesprireWidget> {
  late PrayerTimesPageHorairesprireModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => PrayerTimesPageHorairesprireModel());
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      ),
    );
  }
}
