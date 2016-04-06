require 'json'
require 'net/http'
require 'date'
require 'time'

$HOST = "JIRA-HOST"
$USERNAME = "JIRA-USERNAME"
$PASSWORD = "JIRA-PASSWORD"
$RAPID_VIEW_ID = "RAPID-VIEW-ID"

sprintQuery = "#{$HOST}/rest/greenhopper/1.0/sprintquery/#{$RAPID_VIEW_ID}?includeFutureSprints=false"
sprintReport = "#{$HOST}/rest/greenhopper/1.0/rapid/charts/sprintreport?rapidViewId=#{$RAPID_VIEW_ID}&sprintId=%s"

def fetch(uri)
  request = Net::HTTP::Get.new(uri)
  request.basic_auth $USERNAME, $PASSWORD

  Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
    JSON.parse(http.request(request).body)
  end
end

def scopeChange(contents)
  totalPoints = contents['completedIssuesEstimateSum']['value'] + contents['issuesNotCompletedEstimateSum']['value']
  addedStories = contents['issueKeysAddedDuringSprint'].map { |issue| issue[0] }
  startingPoints = contents['completedIssues'].select { |issue| !issue['estimateStatistic'].nil? && issue['estimateStatistic']['statFieldId'].eql?('customfield_10008') }.reject { |issue| issue['estimateStatistic']['statFieldValue']['value'].nil? || addedStories.include?(issue['key']) }.map { |issue| issue['estimateStatistic']['statFieldValue']['value'] }.reduce(:+)
  startingPoints += contents['issuesNotCompletedInCurrentSprint'].select { |issue| !issue['estimateStatistic'].nil? && issue['estimateStatistic']['statFieldId'].eql?('customfield_10008') }.reject { |issue| issue['estimateStatistic']['statFieldValue']['value'].nil? || addedStories.include?(issue['key']) }.map { |issue| issue['estimateStatistic']['statFieldValue']['value'] }.reduce(:+)

  (((totalPoints - startingPoints) / startingPoints) * 100).round
end

def countWeekendDays(from, to)
  from.upto(to).count { |date| date.saturday? || date.sunday? }
end

def points(contents, statusIds)
  contents.select { |issue| !issue['estimateStatistic'].nil? && issue['estimateStatistic']['statFieldId'].eql?('customfield_10008') && statusIds.include?(issue['statusId']) }.map! { |issue| issue['estimateStatistic']['statFieldValue']['value'] }.compact.reduce(0) { |sum, num| sum + num }
end

SCHEDULER.every '30m', first_in: 0 do |_job|
  # Fetch active sprint
  activeSprint = fetch(URI(sprintQuery))['sprints'].find { |sprint| sprint['state'].eql? 'ACTIVE' }
  # Fetch sprint report for active sprint
  report = fetch(URI(sprintReport % activeSprint['id']))

  startTime = Time.parse(report['sprint']['startDate'])
  startDate = startTime.to_date
  endTime = Time.parse(report['sprint']['endDate'])
  endDate = endTime.to_date
  time = Time.now
  date = time.to_date

  # 1 => 'Open', 10000 => 'To Do', 10003 => 'Analyzing', 10014 => 'Reviewing', 10016 => 'Ready For Sprint', 10027 => 'Ready For Poker', 10031 => 'On hold/blocked'
  toDo = points(report['contents']['issuesNotCompletedInCurrentSprint'], %w(1 10000 10003 10014 10016 10027 10031))
  # 3 => 'In Progress', 10005 => 'Implementing', 10007 => 'Accepting', 10024 => 'Ready for Implementation', 10028 => 'Ready For Verification', 10029 => 'Verifying', 10030 => 'Ready For Acceptance'
  inProgress = points(report['contents']['issuesNotCompletedInCurrentSprint'], %w(3 10005 10007 10024 10028 10029 10030))
  # 6 => 'Closed', 10001 => 'Done'
  done = points(report['contents']['completedIssues'], %w(6 10001))

  totalPoints = (toDo + inProgress + done)
  toDoPercentage = ((100 / totalPoints) * toDo).round
  inProgressPercentage = ((100 / totalPoints) * inProgress).round
  donePercentage = ((100 / totalPoints) * done).round

  daysLeft = date.upto(endDate).reject { |date| date.saturday? || date.sunday? }.count - 1
  timeElapsed = ((((time.to_i - startTime.to_i) - (countWeekendDays(startDate, date) * 86_400)).to_f / ((endTime.to_i - startTime.to_i) - (countWeekendDays(startDate, endDate) * 86_400)).to_f) * 100).round
  workComplete = ((done / totalPoints) * 100).round
  flagged = report['contents']['issuesNotCompletedInCurrentSprint'].count { |issue| issue['flagged'] }
  blocker = report['contents']['issuesNotCompletedInCurrentSprint'].count { |issue| issue['priorityName'].eql?('Blocker') }
  scopeChange = scopeChange(report['contents'])

  chartData = [{type: 'pie', showInLegend: true, dataPoints: [{color: '#426082', y: toDo, legendText: "To Do (#{toDoPercentage}%)"}, {color: '#F3B834', y: inProgress, legendText: "In Progress (#{inProgressPercentage}%)"}, {color: '#13882B', y: done, legendText: "Done (#{donePercentage}%)"}]}]
  healthData = {daysLeft: daysLeft, timeElapsed: "#{timeElapsed}%", workComplete: "#{workComplete}%", flagged: flagged, blocker: blocker, scopeChange: "#{scopeChange}%"}

  send_event('health', container: 'healthChart', chartData: chartData, healthData: healthData, title: 'Overall sprint progress')
end
