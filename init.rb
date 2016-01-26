# -*- coding: utf-8 -*-
# rubocop:disable GlobalVars, SpecialGlobalVars

# Some reading: http://felipec.wordpress.com/2013/11/04/init/

require 'date'
require 'fileutils'

STDOUT.sync = true

$processes = {}

def log(message)
  puts "[#{DateTime.now}] INIT: #{message}"
end

def run!(*args, &block)
  log "Starting: #{args}" if ENV['DEBUG']
  pid = Process.spawn(*args)
  log "Started #{pid}: #{args.join ' '}"
  $processes[pid] = block || ->{ log "#{args.join ' '}: #{$?}" }
  pid
end

def reconfigure! reason=nil
  if $reconf_pid
    if reason
      log "#{reason}, but cannot reconfigure: already running"
    else
      log "Cannot reconfigure: already running"
    end
    return
  end

  if reason
    log "#{reason}, reconfiguring"
  else
    log "Reconfiguring"
  end

  $reconf_pid = run! '/usr/bin/chef-server-ctl', 'reconfigure' do
    log "Reconfiguration finished: #{$?}"
    $reconf_pid = nil
    unless File.exist? '/var/opt/chef-manage/bootstrapped'
      manage_reconfigure! 'Management Not bootstrapped'
    end
  end
end

### Decoupled the Chef-Manage WebUi configuration from the process so that this block is only fired
### when the UI should be configured
def manage_reconfigure! reason=nil
  log "Reconfigure the management interface"
  if $reconf_manage_pid
    if reason
      log "#{reason}, but cannot reconfigure chef-manage: already running"
    else
      log "Cannot reconfigure chef-manage: already running"
    end
    return
  end

  if reason
    log "#{reason}, reconfiguring"
  else
    log "Reconfiguring"
  end
  
  ## Need to remove the link to get around a bug where chef-manage will fail to do the initial configuration due to
  ## this log link.  Dumb  
  FileUtils.rm('/var/log/chef-manage', :force => true)

  $reconf_manage_pid = run! '/usr/bin/chef-manage-ctl', 'reconfigure' do
    #### This bit will ensure that this is a run-once process.
    File.write "/var/opt/chef-manage/bootstrapped", "Chef-Manage has been bootstrapped"
    $reconf_manage_pid = nil

    log "Move the chef-manage log directory to the Volume"
    FileUtils.mv("/var/log/chef-manage", '/var/opt/chef-manage/log')
    log "Delete the original log directory"
    #FileUtils.rm('/var/log/chef-manage', :force => true)
    log "Link the original log path to new location on the Volume"
    FileUtils.ln_s('/var/opt/chef-manage/log','/var/log/chef-manage',  :force => true)
    log "Reconfiguration finished: #{$?}"
  end

end


def shutdown!
  unless $runsvdir_pid
    log "ERROR: no runsvdir pid at exit"
    exit 1
  end

  if $reconf_pid
    log "Reconfigure running as #{$reconf_pid}, stopping..."
    Process.kill 'TERM', $reconf_pid
    (1..5).each do
      if $reconf_pid
        sleep 1
      else
        break
      end
    end
    if $reconf_pid
      Process.kill 'KILL', $reconf_pid
    end
  end

  ### We need to stop the WebUI first and then cleanly kill the monitor pids
  run! '/usr/bin/chef-manage-ctl', 'stop' do
    log 'opscode-manage-ctl stop finished, stopping runsvdir'
    Process.kill('HUP', $manage_runsvdir_pid)
  end

  run! '/usr/bin/chef-server-ctl', 'stop' do
    log 'chef-server-ctl stop finished, stopping runsvdir'
    Process.kill('HUP', $runsvdir_pid)
  end
end

### Separate the management WebUI start from the rest of the process to ensure that everything
### loads correctly
def start_manage
  $manage_runsvdir_pid = run! '/opt/chef-manage/embedded/bin/runsvdir-start' do
    log "runsvdir exited: #{$?}"
    if $?.success? || $?.exitstatus == 111
      exit
    else
      exit $?.exitstatus
    end
  end
end  

log "Starting #{$PROGRAM_NAME}"

{ shmmax: 17179869184, shmall: 4194304 }.each do |param, value|
  if ( actual = File.read("/proc/sys/kernel/#{param}").to_i ) < value
    log "kernel.#{param} = #{actual}, setting to #{value}."
    begin
      File.write "/proc/sys/kernel/#{param}", value.to_s
    rescue
      log "Cannot set kernel.#{param} to #{value}: #{$!}"
      log "You may need to run the container in privileged mode or set sysctl on host."
      raise
    end
  end
end

log 'Preparing configuration ...'
FileUtils.mkdir_p %w'/var/opt/opscode/log /var/opt/opscode/etc /.chef/env', verbose: true
FileUtils.cp '/.chef/chef-server.rb', '/var/opt/opscode/etc', verbose: true

%w'PUBLIC_URL OC_ID_ADMINISTRATORS'.each do |var|
  File.write(File.join('/.chef/env', var), ENV[var].to_s)
end

$runsvdir_pid = run! '/opt/opscode/embedded/bin/runsvdir-start' do
  log "runsvdir exited: #{$?}"
  if $?.success? || $?.exitstatus == 111
    exit
  else
    exit $?.exitstatus
  end
end

### Signal commands are used to execute various functions.
### These signals can be fired off by using the docker kill -s {SIGNAL} {CONTAINERID} command
Signal.trap 'TERM' do
  shutdown!
end

Signal.trap 'INT' do
  shutdown!
end

Signal.trap 'HUP' do
  reconfigure! 'Got SIGHUP'
end

Signal.trap 'USR1' do
  log 'Chef Server status:'
  run! '/usr/bin/chef-server-ctl', 'status'
end

Signal.trap 'USR2' do
  log 'Remove the Chef-Management service'
  FileUtils.rm("/var/opt/opscode/nginx/etc/addon.d/*chef-manage*",  :force => true)
end

### This check will prevent tons of errors if the WebUI package is not installed.  We want these services
### started before the reconfiguration of the chef-manage-ctl to prevent errors.
if File.exist? '/opt/chef-manage/embedded/bin/runsvdir-start'
  start_manage 
end

### Reconfiguration is automatic when booting if this file does not exist.  On first boot, it will be created 
### after the reconfigure completes.  
unless File.exist? '/var/opt/chef-manage/bootstrapped'
  log "We must first reconfigure this Chef instance to prepare it for the management console"
  reconfigure! 'Chef Server not bootstrapped'
end


loop do
  log $? if ENV['DEBUG']
  handler = $processes.delete(Process.wait)
  handler.call if handler
end
