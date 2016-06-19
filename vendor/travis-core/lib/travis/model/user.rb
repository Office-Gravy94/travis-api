require 'gh'
require 'travis/model'
require 'travis/github/oauth'

class User < Travis::Model
  require 'travis/model/user/oauth'
  require 'travis/model/user/renaming'

  has_many :tokens, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :organizations, through: :memberships
  has_many :permissions, dependent: :destroy
  has_many :repositories, through: :permissions
  has_many :emails, dependent: :destroy

  attr_accessible :name, :login, :email, :github_id, :github_oauth_token, :gravatar_id, :locale, :education, :first_logged_in_at

  before_create :set_as_recent
  after_create :create_a_token
  after_commit :sync, on: :create
  before_save :track_previous_changes

  serialize :github_scopes

  serialize :github_oauth_token, Travis::Model::EncryptedColumn.new

  class << self
    def with_permissions(permissions)
      where(:permissions => permissions).includes(:permissions)
    end

    def authenticate_by(options)
      options = options.symbolize_keys

      if user = User.find_by_login(options[:login])
        user if user.tokens.any? { |t| t.token == options[:token] }
      end
    end

    def find_or_create_for_oauth(payload)
      Oauth.find_or_create_by(payload)
    end

    def with_github_token
      where("github_oauth_token IS NOT NULL and github_oauth_token != ''")
    end

    def with_email(email_address)
      Email.where(email: email_address).first.try(:user)
    end
  end

  def to_json
    keys = %w/id login email name locale github_id gravatar_id is_syncing synced_at updated_at created_at/
    { 'user' => attributes.slice(*keys) }.to_json
  end

  def permission?(roles, options = {})
    roles, options = nil, roles if roles.is_a?(Hash)
    scope = permissions.where(options)
    scope = scope.by_roles(roles) if roles
    scope.any?
  end

  def first_sync?
    synced_at.nil?
  end

  def sync
    Travis.run_service(:sync_user, self) # TODO move to the authentication endpoint, or create a separate service
  end

  def syncing?
    is_syncing?
  end

  def service_hook(options = {})
    service_hooks(options).first
  end

  def service_hooks(options = {})
    hooks = repositories
    unless options[:all]
      hooks = hooks.administratable
    end
    hooks = hooks.includes(:permissions).
              select('repositories.*, permissions.admin as admin, permissions.push as push').
              order('owner_name, name')
    # TODO remove owner_name/name once we're on api everywhere
    if options.key?(:id)
      hooks = hooks.where(options.slice(:id))
    elsif options.key?(:owner_name) || options.key?(:name)
      hooks = hooks.where(options.slice(:id, :owner_name, :name))
    end
    hooks
  end

  def organization_ids
    @organization_ids ||= memberships.map(&:organization_id)
  end

  def repository_ids
    @repository_ids ||= permissions.map(&:repository_id)
  end

  def recently_signed_up?
    !!@recently_signed_up
  end

  def profile_image_hash
    # TODO:
    #   If Github always sends valid gravatar_id in oauth payload (need to check that)
    #   then these fallbacks (email hash and zeros) are superfluous and can be removed.
    gravatar_id.presence || (email? && Digest::MD5.hexdigest(email)) || '0' * 32
  end

  def github_scopes
    github_oauth_token && read_attribute(:github_scopes) || []
  end

  def avatar_url
    "https://0.gravatar.com/avatar/#{profile_image_hash}"
  end

  def previous_changes
    @previous_changes ||= {}
  end

  def reload
    @previous_changes = nil
    super
  end

  def inspect
    github_oauth_token ? super.gsub(github_oauth_token, '[REDACTED]') : super
  end

  protected

    def track_previous_changes
      @previous_changes = changes
    end

    def set_as_recent
      @recently_signed_up = true
    end

    def create_a_token
      self.tokens.create!
    end
end
