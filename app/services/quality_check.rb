class QualityCheck
  attr_accessor :issues, :changeset

  def initialize(changeset: nil)
    @issues = []
    @changeset = changeset
  end

  def check
    raise NotImplementedError
  end
end

class QualityCheck::StationHierarchyQualityCheck < QualityCheck
  STOP_PLATFORM_PARENT_DIST_GAP_THRESHOLD = 500.0
  MINIMUM_DIST_BETWEEN_PLATFORMS = 0.0

  def check
    # consider consolidating with GeometryQualityCheck if performance a concern

    parent_stops_to_check = Set.new(self.changeset.stops_created_or_updated.map(&:onestop_id))
    parent_stops_with_changing_platforms = Set.new

    self.changeset.stop_platforms_created_or_updated.each do |stop_platform|
      parent_stops_to_check << stop_platform.parent_stop.onestop_id
      parent_stops_with_changing_platforms << stop_platform.parent_stop.onestop_id
    end

    parent_stops_with_changing_platforms.each do |parent_stop_onestop_id|
      parent_stop = Stop.find_by_onestop_id!(parent_stop_onestop_id)
      # need to look at all platforms of parent stop, not just the ones in changeset
      # and avoid creating duplicate issues
      all_siblings = Set.new(parent_stop.stop_platforms.map(&:onestop_id))
      all_changing = Set.new(self.changeset.stop_platforms_created_or_updated.map(&:onestop_id))
      changing_siblings_to_check = all_siblings & all_changing
      static_siblings_to_check = all_siblings - all_changing

      changing_siblings_to_check.to_a.combination(2).each do |stop_platform_1_onestop_id, stop_platform_2_onestop_id|
        stop_platform_1 = StopPlatform.find_by_onestop_id!(stop_platform_1_onestop_id)
        stop_platform_2 = StopPlatform.find_by_onestop_id!(stop_platform_2_onestop_id)
        self.distance_between_stop_platforms(stop_platform_1, stop_platform_2)
      end

      changing_siblings_to_check.each do |changing_stop_platform_onestop_id|
        changing_stop_platform = StopPlatform.find_by_onestop_id!(changing_stop_platform_onestop_id)
        static_siblings_to_check.each do |static_stop_platform_onestop_id|
          static_stop_platform = StopPlatform.find_by_onestop_id!(static_stop_platform_onestop_id)
          self.distance_between_stop_platforms(changing_stop_platform, static_stop_platform)
        end
      end
    end

    parent_stops_to_check.each do |parent_stop_onestop_id|
      parent_stop = Stop.find_by_onestop_id!(parent_stop_onestop_id)
      parent_stop.stop_platforms.each do |stop_platform|
        self.stop_platform_parent_distance_gap(parent_stop, stop_platform)
      end
    end

    self.issues
  end

  def stop_platform_parent_distance_gap(parent_stop, stop_platform)
    if (parent_stop.geometry_centroid.distance(stop_platform.geometry_centroid) > STOP_PLATFORM_PARENT_DIST_GAP_THRESHOLD)
      issue = Issue.new(created_by_changeset: self.changeset,
                        issue_type: 'stop_platform_parent_distance_gap',
                        details: "A plataforma da paragem #{stop_platform.parent_stop_onestop_id} está demasiado distante da paragem pai #{parent_stop.onestop_id}.")
      issue.entities_with_issues.new(entity: parent_stop, issue: issue, entity_attribute: 'geometry')
      issue.entities_with_issues.new(entity: stop_platform, issue: issue, entity_attribute: 'geometry')
      self.issues << issue
    end
  end

  def distance_between_stop_platforms(stop_platform, other_stop_platform)
    if (stop_platform.geometry_centroid.distance(other_stop_platform.geometry_centroid) <= MINIMUM_DIST_BETWEEN_PLATFORMS)
      issue = Issue.new(created_by_changeset: self.changeset,
                        issue_type: 'stop_platforms_too_close',
                        details: "A plataforma #{stop_platform.onestop_id} está demasiado próxima da plataforma #{other_stop_platform.onestop_id}")
      issue.entities_with_issues.new(entity: stop_platform, issue: issue, entity_attribute: 'geometry')
      issue.entities_with_issues.new(entity: other_stop_platform, issue: issue, entity_attribute: 'geometry')
      self.issues << issue
    end
  end
end

class QualityCheck::GeometryQualityCheck < QualityCheck

  LAST_STOP_DISTANCE_LENIENCY = 5.0 #meters
  MINIMUM_DIST_BETWEEN_STOP_PARENTS = 10.0

  # some aggregate stats on rsp distance calculation
  attr_accessor :distance_issues, :distance_issue_tests

  def distance_score
    if self.changeset.imported_from_feed
      import_score = ((self.distance_issue_tests - self.distance_issues).round(1)/self.distance_issue_tests).round(5) rescue 1.0
      log "Feed: #{self.changeset.imported_from_feed.onestop_id} importada com o Valhalla Import Score: #{import_score} #{self.distance_issue_tests} Stop-RouteStopPattern pares foram testados e foram encontrados #{self.distance_issues} problemas de distância."
    end
  end

  def check
    self.distance_issues = 0
    self.distance_issue_tests = 0

    import = !self.changeset.imported_from_feed.nil?
    rsps_to_evaluate = Set.new
    stop_rsp_gap_pairs =  Set.new

    self.changeset.route_stop_patterns_created_or_updated.each do |rsp|
      rsps_to_evaluate << rsp.onestop_id
      Stop.where(onestop_id: rsp.stop_pattern).each do |stop|
        stop_rsp_gap_pairs << [rsp.onestop_id, stop.onestop_id]
      end
      self.rsp_line_only_stop_points(rsp)
      # other checks on rsp-exclusive attributes go here
    end

    self.changeset.stops_created_or_updated.each do |stop|
      unless import
        RouteStopPattern.where{ stop_pattern.within(stop.onestop_id) }.each do |rsp|
          rsps_to_evaluate << rsp.onestop_id
          stop_rsp_gap_pairs << [rsp.onestop_id, stop.onestop_id]
        end
      end
      if stop.geometry[:coordinates].eql?([0.0, 0.0])
        issue = Issue.new(created_by_changeset: self.changeset,
                          issue_type: 'stop_position_inaccurate',
                          details: "A paragem #{stop.onestop_id} não está a servir local algum.")
        issue.entities_with_issues.new(entity: stop, issue: issue, entity_attribute: 'geometry')
        self.issues << issue
      end
      # self.distances_between_stops(stop)
      # other checks on stop-exclusive attributes go here
    end

    rsps_to_evaluate.each do |onestop_id|
      rsp = RouteStopPattern.find_by_onestop_id!(onestop_id)
      # handle the case of 1 stop trips
      next if rsp.geometry[:coordinates].uniq.size == 1
      rsp.stop_pattern.each_index do |i|
        self.distances_between_rsp_stops(rsp, i)
        self.stop_distances_accuracy(rsp, i)
      end
    end

    stop_rsp_gap_pairs.each do |rsp_onestop_id, stop_onestop_id|
      rsp = RouteStopPattern.find_by_onestop_id!(rsp_onestop_id)
      stop = Stop.find_by_onestop_id!(stop_onestop_id)
      # handle the case of 1 stop trips
      self.stop_rsp_distance_gap(stop, rsp) unless rsp.geometry[:coordinates].uniq.size == 1
    end

    self.distance_issue_tests = rsps_to_evaluate.map {|onestop_id| RouteStopPattern.find_by_onestop_id!(onestop_id).stop_pattern.size }.reduce(:+)
    self.distance_issues = Set.new(self.issues.select {|ewi| ['distance_calculation_inaccurate'].include?(ewi.issue_type) }.each {|issue| issue.entities_with_issues.map(&:entity_id) }).size
    distance_score

    self.issues
  end

  def rsp_line_only_stop_points(rsp)
    if rsp.stop_pattern.size == rsp.geometry[:coordinates].size
      # RouteStopPattern geometry coordinates and Stop geometry coordinates can have different decimal precision.
      if rsp.stop_pattern.map{ |onestop_id| Stop.find_by_onestop_id!(onestop_id).geometry[:coordinates].map{ |coord| coord.round(RouteStopPattern::COORDINATE_PRECISION) } }.eql?(rsp.geometry[:coordinates])
        issue = Issue.new(created_by_changeset: self.changeset,
                          issue_type: 'rsp_line_only_stop_points',
                          details: "RouteStopPattern #{rsp.onestop_id} tem uma linha geométrica gerada pelas coordenadas das paragens.")
        issue.entities_with_issues.new(entity: rsp, issue: issue, entity_attribute: 'geometry')
        self.issues << issue
      end
    end
  end

  def distances_between_stops(stop)
    # check distance between stop and any other stop in datastore or belonging to operator
  end

  def stop_rsp_distance_gap(stop, rsp)
    if Geometry::OutlierStop.outlier_stop(stop, rsp)
      issue = Issue.new(created_by_changeset: self.changeset,
                        issue_type: 'stop_rsp_distance_gap',
                        details: "A paragem #{stop.onestop_id} e a RouteStopPattern #{rsp.onestop_id} estão demasiado distantes.")
      issue.entities_with_issues.new(entity: stop, issue: issue, entity_attribute: 'geometry')
      issue.entities_with_issues.new(entity: rsp, issue: issue, entity_attribute: 'geometry')
      self.issues << issue
    end
  end

  def distances_between_rsp_stops(rsp, index)
    if (index != 0)
      stop1 = Stop.find_by_onestop_id!(rsp.stop_pattern[index])
      stop2 = Stop.find_by_onestop_id!(rsp.stop_pattern[index-1])
      if (!stop1.onestop_id.eql?(stop2.onestop_id) && stop1.geometry_centroid.distance(stop2.geometry_centroid) < MINIMUM_DIST_BETWEEN_STOP_PARENTS)
        issue = Issue.new(created_by_changeset: self.changeset,
                          issue_type: 'rsp_stops_too_close',
                          details: "RouteStopPattern #{rsp.onestop_id}. Paragem #{stop1.onestop_id}, número #{index-1}, tem coordenadas (#{stop1.geometry_centroid.to_s}) demasiado próximas da paragem #{stop2.onestop_id}, número #{index}, com as coordenadas (#{stop2.geometry_centroid.to_s})")
        issue.entities_with_issues.new(entity: rsp, issue: issue, entity_attribute: 'geometry')
        issue.entities_with_issues.new(entity: stop1, issue: issue, entity_attribute: 'geometry')
        issue.entities_with_issues.new(entity: stop2, issue: issue, entity_attribute: 'geometry')
        self.issues << issue
      end
    end
  end

  def stop_distances_accuracy(rsp, index)
    geometry_length = rsp[:geometry].length
    if (index != 0)
      stop1 = rsp.stop_pattern[index-1]
      stop2 = rsp.stop_pattern[index]
      if (rsp.stop_distances[index-1] == rsp.stop_distances[index])
        unless stop2.eql? stop1
          unless (Stop.find_by_onestop_id!(stop1).geometry_centroid.distance(Stop.find_by_onestop_id!(stop2).geometry_centroid) < 1.0)
            issue = Issue.new(created_by_changeset: self.changeset,
                              issue_type: 'distance_calculation_inaccurate',
                              details: "Cálculo de distância impreciso. A Paragem #{stop2}, número #{index+1}/#{rsp.stop_pattern.size}, da RouteStopPattern #{rsp.onestop_id} tem a mesma distância (#{rsp.stop_distances[index]} m) que a Paragem #{stop1}. Distâncias: #{rsp.stop_distances}")
            issue.entities_with_issues.new(entity: rsp, issue: issue, entity_attribute: 'stop_distances')
            issue.entities_with_issues.new(entity: OnestopId.find_current_and_old!(stop1), issue: issue, entity_attribute: 'geometry')
            issue.entities_with_issues.new(entity: OnestopId.find_current_and_old!(stop2), issue: issue, entity_attribute: 'geometry')
            issue.entities_with_issues.new(entity: OnestopId.find_current_and_old!(rsp.stop_pattern[index+1]), issue: issue, entity_attribute: 'geometry') if index < rsp.stop_pattern.size - 1
            self.issues << issue
          end
        end
      elsif (rsp.stop_distances[index-1] > rsp.stop_distances[index])
        issue = Issue.new(created_by_changeset: self.changeset,
                          issue_type: 'distance_calculation_inaccurate',
                          details: "Cálculo de distância impreciso. A Paragem #{stop2}, número #{index+1}/#{rsp.stop_pattern.size}, da RouteStopPattern #{rsp.onestop_id} ocorre após a Paragem #{stop1}, mas tem uma distância de (#{rsp.stop_distances[index]} m) a menos que a Paragem #{stop1} com a distância de (#{rsp.stop_distances[index-1]} m). Distâncias: #{rsp.stop_distances}")
        issue.entities_with_issues.new(entity: rsp, issue: issue, entity_attribute: 'stop_distances')
        issue.entities_with_issues.new(entity: OnestopId.find_current_and_old!(rsp.stop_pattern[index-2]), issue: issue, entity_attribute: 'geometry') unless index < 2
        issue.entities_with_issues.new(entity: OnestopId.find_current_and_old!(stop1), issue: issue, entity_attribute: 'geometry')
        issue.entities_with_issues.new(entity: OnestopId.find_current_and_old!(stop2), issue: issue, entity_attribute: 'geometry')
        self.issues << issue
      end
    end
    if ((rsp.stop_distances[index] - geometry_length) > LAST_STOP_DISTANCE_LENIENCY)
      issue = Issue.new(created_by_changeset: self.changeset,
                        issue_type: 'distance_calculation_inaccurate',
                        details: "Cálculo de distância impreciso. A Paragem #{stop2}, número #{index+1}/#{rsp.stop_pattern.size}, da RouteStopPattern #{rsp.onestop_id} tem uma distância de (#{rsp.stop_distances[index]} m), que é superior ao comprimento total da geometria, #{geometry_length}. Distâncias: #{rsp.stop_distances}")
      issue.entities_with_issues.new(entity: rsp, issue: issue, entity_attribute: 'stop_distances')
      issue.entities_with_issues.new(entity: OnestopId.find_current_and_old!(stop1), issue: issue, entity_attribute: 'geometry') unless index < 1
      issue.entities_with_issues.new(entity: OnestopId.find_current_and_old!(stop2), issue: issue, entity_attribute: 'geometry')
      issue.entities_with_issues.new(entity: OnestopId.find_current_and_old!(rsp.stop_pattern[index+1]), issue: issue, entity_attribute: 'geometry') if index < rsp.stop_pattern.size - 1
      self.issues << issue
    end
  end
end
