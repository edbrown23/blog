#!/usr/bin/env ruby

require 'yaml'
require 'pry'

POST_URL= 'https://edbrown23.github.io/blog'

def posts
  return to_enum(:posts) unless block_given?

  Dir.entries('_posts').sort.each do |post|
    yield post unless File.directory?(post)
  end
end

def extract_post_info(post_filename)
  filename_info = {
    path: post_filename,
    year: post_filename[0...4],
    month: post_filename[5..6],
    day: post_filename[8..9],
    title: post_filename[11...-3]
  }

  return filename_info if filename_info[:title].nil?

  File.open("_posts/#{post_filename}", 'rb') do |file|
    raw_meta = file.first(4)
    meta = YAML.unsafe_load(raw_meta.join("\n"))

    filename_info.merge!({
      human_title: meta['title']
    })
  end

  filename_info
end

def update_footer(post, last_post:, next_post: nil)
  # remove the existing footer
  File.open('tmp.md', 'wb') do |output_file|
    File.open("_posts/#{post[:path]}", 'rb').each do |input_line|
      break if input_line.include?('<hr>')

      output_file << input_line
    end
  end

  File.open('tmp.md', 'ab') do |output_file|
    unless last_post.nil?
      output_file << <<~LINES
      <hr>

      Last week's post: [#{last_post[:human_title]}](#{POST_URL}/#{last_post[:year]}/#{last_post[:month]}/#{last_post[:day]}/#{last_post[:title]})

      LINES
    end

    break if next_post.nil?

    if last_post.nil?
      output_file << <<~LINES
      <hr>

      LINES
    end

    output_file << <<~LINES
    Next week's post: [#{next_post[:human_title]}](#{POST_URL}/#{next_post[:year]}/#{next_post[:month]}/#{next_post[:day]}/#{next_post[:title]})

    LINES
  end

  File.open("_posts/#{post[:path]}", 'wb') do |final_out|
    File.open('tmp.md', 'rb').each do |input|
      final_out << input
    end
  end
end

posts.map(&method(:extract_post_info)).each_cons(3).with_index do |(l, c, n), i|
  if i == 0
    update_footer(l, last_post: nil, next_post: n)
  end

  update_footer(c, last_post: l, next_post: n)

  # each_cons is always going to stop 2 before the end of the list
  if i >= posts.count - 3
    update_footer(n, last_post: c, next_post: nil)
  end
end
