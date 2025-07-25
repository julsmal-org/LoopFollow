// LoopFollow
// TaskScheduler.swift
// Created by Jonas Björkert.

import Foundation
import UIKit

enum TaskID: CaseIterable {
    case profile
    case deviceStatus
    case treatments
    case fetchBG
    case minAgoUpdate
    case calendarWrite
    case alarmCheck
}

struct ScheduledTask {
    var nextRun: Date
    var action: () -> Void
}

class TaskScheduler {
    static let shared = TaskScheduler()

    private let queue = DispatchQueue(label: "com.LoopFollow.TaskSchedulerQueue")

    private var tasks: [TaskID: ScheduledTask] = [:]
    private var currentTimer: DispatchSourceTimer?

    private init() {}

    // MARK: - Public API

    func scheduleTask(id: TaskID, nextRun: Date, action: @escaping () -> Void) {
        queue.async {
            let timeString = self.formatTime(nextRun)
            LogManager.shared.log(category: .taskScheduler, message: "scheduleTask(\(id)): next run = \(timeString)", isDebug: true)

            self.tasks[id] = ScheduledTask(nextRun: nextRun, action: action)
            self.rescheduleTimer()
        }
    }

    func rescheduleTask(id: TaskID, to newRunDate: Date) {
        // let timeString = formatTime(newRunDate)
        // LogManager.shared.log(category: .taskScheduler, message: "Reschedule Task \(id): next run = \(timeString)", isDebug: true)

        queue.async {
            guard var existingTask = self.tasks[id] else { return }
            existingTask.nextRun = newRunDate
            self.tasks[id] = existingTask
            self.checkTasksNow()
        }
    }

    func checkTasksNow() {
        queue.async {
            self.fireOverdueTasks()
            self.rescheduleTimer()
        }
    }

    // MARK: - Private

    private func rescheduleTimer() {
        currentTimer?.cancel()
        currentTimer = nil

        guard let (_, earliestTask) = tasks.min(by: { $0.value.nextRun < $1.value.nextRun }) else {
            LogManager.shared.log(category: .taskScheduler, message: "No tasks, no timer scheduled.")
            return
        }

        let interval = earliestTask.nextRun.timeIntervalSinceNow
        let safeInterval = max(interval, 0)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + safeInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.fireOverdueTasks()
            self.rescheduleTimer()
        }
        currentTimer = timer
        timer.resume()
    }

    private func fireOverdueTasks() {
        BackgroundAlertManager.shared.scheduleBackgroundAlert()

        let now = Date()

        for taskID in TaskID.allCases {
            guard let task = tasks[taskID], task.nextRun <= now else {
                continue
            }

            var updatedTask = task
            updatedTask.nextRun = .distantFuture
            tasks[taskID] = updatedTask

            // LogManager.shared.log(category: .taskScheduler, message: "Executing Task \(taskID)", isDebug: true)

            DispatchQueue.main.async {
                task.action()
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
