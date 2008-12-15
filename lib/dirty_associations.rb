module DirtyAssociations
  
  VERSION = '0.1.2'
  
  class << self
    def included base
      base.extend ClassMethods
    end
  end
  
  module ClassMethods
    def has_dirty_associations(*associations)
      include InstanceMethods

      options = associations.extract_options!
      
      associations_to_watch = case associations
        when [], [:all]  then
          self.reflections.keys
        when [:children] then
          self.reflections.select { |assoc, reflection|
            [:has_one, :has_many, :has_and_belongs_to_many, :composed_of].include? reflection.macro }.map(&:first)
        when [:parents]  then
          self.reflections.select { |assoc, reflection|
            [:belongs_to, :has_and_belongs_to_many].include? reflection.macro }.map(&:first)
        else
          associations
        end  
        
      write_inheritable_attribute(:watched_associations, associations_to_watch)

      class_eval do
        default_scope :include => associations_to_watch
        
        def self.watched_associations
          read_inheritable_attribute :watched_associations
        end
        
        class <<self
          alias_method :watched_association, :watched_associations
        end
        
        # Override the default_scope that includes all associations
        def self.all
          with_exclusive_scope { super }
        end        
      end

      associations_to_watch.each do |association|        
        define_method "#{association}_changes" do
          returning({}) do |hash|
            records_from_association(association).select(&:changed?).each do |instance|
              hash[instance.id] = instance.changes
            end            
          end
        end
        
        define_method "any_#{association}_changed?" do
            records_from_association(association).collect(&:changed?).any?
        end
        alias_method :"#{association}_changed?", :"any_#{association}_changed?"
        
        define_method "#{association}_changed" do
          returning({}) do |hash|
            records_from_association(association).select(&:changed?).each do |instance|
              hash[instance.id] = instance.changed
            end            
          end
        end
        
        unless options[:update_only]
          associated_class = self.reflections[association].active_record
          
          cattr_accessor :"cached_#{association}"
          
          class << associated_class
            # add any necassary callbacks here
            # e.g. before_save
          end
          
          define_method "cache_#{association}!" do
            puts 'WRITING TO CACHE'
            self.class.send(:"cached_#{association}=", records_from_association(association, true))
          end
          
          define_method "#{association}_from_cache" do
            self.class.send(:"cached_#{association}")
          end
          
          
          new_method_name = "new_#{association}"          
          define_method new_method_name do
            records_from_association(association).select(&:new_record?)
          end
          
          define_method "#{new_method_name}?" do
            self.send(new_method_name).any?
          end
          
          
          edited_method_name = "edited_#{association}"          
          define_method edited_method_name do
            records_from_association(association).select do |record|
              record.changed? && !record.new_record?
            end
          end
          
          define_method "#{edited_method_name}?" do
            self.send(edited_method_name).any?
          end
          
          
          deleted_method_name = "deleted_#{association}"
          define_method deleted_method_name do
            records_from_association(association).select(&:frozen?)
          end          
          
          define_method "#{deleted_method_name}?" do
            self.send(deleted_method_name).any?
          end 
        end  
      end  
    end
    alias_method :has_dirty_association, :has_dirty_associations
  end
  
  module InstanceMethods
    def watched_associated_records
      self.class.watched_associations.map { |assoc| self.send(assoc) }.flatten
    end
    
    def cache_associated!
      self.class.watched_associations.each { |assoc| send(:"cache_#{assoc}!") }
    end
    
    def associated_from_cache
      returning({}) do |hash|
        self.class.watched_associations.each { |assoc| hash[assoc] = send(:"#{assoc}_from_cache") }
      end
    end

    private

    def records_from_association(association, clone = false) 
      records = Array(self.send(association))
      clone ? records.collect(&:clone) : records
    end
  end
end

ActiveRecord::Base.send(:include, DirtyAssociations) if Object.const_defined?("ActiveRecord")