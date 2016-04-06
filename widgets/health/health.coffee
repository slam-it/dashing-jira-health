class Dashing.Health extends Dashing.Canvasjs

  ready: ->
    @chart @get('container'), @get('chartData'), @get('title')
    @addClass()

  onData: (data) ->
    @chart @get('container'), @get('chartData'), @get('title')
    @addClass()

  addClass: =>
    healthData = @get('healthData')
    scope = $(@node).find(".scope")
    blocker = $(@node).find(".blocker")
    flagged = $(@node).find(".flagged")
    scope.addClass("change") if (healthData['scopeChange'] != "0%")
    blocker.addClass("fade") if (healthData['blocker'] == 0)
    flagged.addClass("fade") if (healthData['flagged'] == 0)
