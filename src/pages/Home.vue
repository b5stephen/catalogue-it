<template>
  <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
  <Card name="plaines">Model Plaines</Card>
  <Card name="cards">Safety Cards</Card>
  <Card name="house">House Items</Card>
  </div>
</template>

<script lang="ts">
import { defineComponent } from 'vue'
import Card from '../components/cards/CatalogueSelector.vue'
export default defineComponent({
  name: 'Home',
  components: {
    Card
  },
  props: {

  },
  setup: () => {
    
    return {  }
  }
})
</script>

<style scoped>

</style>
