import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/trip.dart';
import '../providers/trips_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/card.dart';
import '../widgets/stat.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TripsProvider>(context);
    final trips = provider.trips;

    final summary = trips.isEmpty
        ? {'avgTime': 0.0, 'totalPreempts': 0, 'avgConf': 0.0}
        : {
            'avgTime': trips.map((t) => t.travelTime).reduce((a, b) => a + b) / trips.length,
            'totalPreempts': trips.map((t) => t.preemptions).reduce((a, b) => a + b),
            'avgConf': trips.map((t) => t.confidence).reduce((a, b) => a + b) / trips.length,
          };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.card,
            foregroundColor: AppColors.foreground,
            side: BorderSide(color: AppColors.border),
          ),
        ),
        title: const Text(
          'Trip History',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.foreground,
          ),
        ),
        centerTitle: true,
        actions: [
          const SizedBox(width: 40),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(
            height: 0.5,
            color: AppColors.border,
          ),
        ),
      ),
      body: trips.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inbox, size: 36, color: AppColors.mutedForeground),
                  const SizedBox(height: 10),
                  const Text(
                    'No trips logged yet',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Summary Card
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'All time',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Stat(
                            label: 'Avg travel',
                            value: '${summary['avgTime']!.toStringAsFixed(1)}s',
                            color: AppColors.success,
                          ),
                          Stat(
                            label: 'Preempts',
                            value: '${summary['totalPreempts']}',
                            color: AppColors.accent,
                          ),
                          Stat(
                            label: 'Avg conf.',
                            value: '${summary['avgConf']!.toStringAsFixed(0)}%',
                            color: const Color(0xFF60A5FA),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Trip Cards
                ...trips.map((trip) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _TripCard(trip: trip),
                    )),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;

  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final accent = trip.criticality == Criticality.critical
        ? AppColors.critical
        : trip.criticality == Criticality.high
            ? AppColors.accent
            : AppColors.success;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.date,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${trip.time} · ${trip.driverId}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      trip.criticality.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Stat(
                label: 'Travel',
                value: '${trip.travelTime.toStringAsFixed(1)}s',
                color: AppColors.success,
              ),
              Stat(label: 'Distance', value: '${trip.distance.toStringAsFixed(1)} km'),
              Stat(
                label: 'Preempts',
                value: '${trip.preemptions}',
                color: AppColors.accent,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(AppColors.radius),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: trip.confidence / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF60A5FA),
                      borderRadius: BorderRadius.circular(AppColors.radius),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'ML confidence',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
