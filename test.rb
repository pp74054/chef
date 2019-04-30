def rl
  load "test.rb"
  nil
end

load "chef/knife/bootstrap/train_connector.rb"

[:uri, :proto, :opts].each do |m|
  define_method("#{m}=") { |v| instance_variable_set("@#{m}", v) }
  define_method("#{m}") { instance_variable_get("@#{m}") }
end

def c
  @c ||= Chef::Knife::Bootstrap::TrainConnector.new(@uri, @proto, @opts)
end

def c=(v)
  @c = v
end

BS = Chef::Knife::Bootstrap
TC = Chef::Knife::Bootstrap::TrainConnector

@uri ||= "ssh://localhost"
@opts ||= {}
@proto ||= "ssh"
