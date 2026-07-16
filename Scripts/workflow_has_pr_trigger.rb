#!/usr/bin/env ruby

require "psych"

PR_EVENTS = %w[pull_request pull_request_target].freeze

def collect_anchors(node, anchors)
  unless node.is_a?(Psych::Nodes::Alias)
    anchor = node.respond_to?(:anchor) ? node.anchor : nil
    anchors[anchor] = node if anchor && !anchor.empty?
  end
  children = node.respond_to?(:children) ? node.children : nil
  return unless children

  children.each { |child| collect_anchors(child, anchors) }
end

def resolve_alias(node, anchors, seen = {})
  while node.is_a?(Psych::Nodes::Alias)
    anchor = node.anchor
    raise "cyclic YAML alias #{anchor}" if seen[anchor]

    seen = seen.merge(anchor => true)
    node = anchors.fetch(anchor) { raise "unresolved YAML alias #{anchor}" }
  end
  node
end

def scalar_value(node, anchors)
  node = resolve_alias(node, anchors)
  node.value if node.is_a?(Psych::Nodes::Scalar)
end

def pr_trigger_node?(node, anchors)
  node = resolve_alias(node, anchors)
  case node
  when Psych::Nodes::Scalar
    PR_EVENTS.include?(node.value)
  when Psych::Nodes::Sequence
    node.children.any? { |child| PR_EVENTS.include?(scalar_value(child, anchors)) }
  when Psych::Nodes::Mapping
    node.children.each_slice(2).any? do |key, value|
      key_value = scalar_value(key, anchors)
      PR_EVENTS.include?(key_value) || (key_value == "<<" && pr_trigger_node?(value, anchors))
    end
  else
    false
  end
end

begin
  path = ARGV.fetch(0)
  document = Psych.parse_file(path)
  root = document&.root
  raise "workflow root must be a mapping" unless root.is_a?(Psych::Nodes::Mapping)

  anchors = {}
  collect_anchors(document, anchors)

  has_pr_trigger = root.children.each_slice(2).any? do |key, value|
    scalar_value(key, anchors) == "on" && pr_trigger_node?(value, anchors)
  end

  exit(has_pr_trigger ? 0 : 1)
rescue StandardError => error
  warn "workflow trigger parse error: #{error.message}"
  exit 2
end
