<template>
    <RouterLink :to="{name: 'Catalogue', params: { name: name }}" class="bg-gray-200 w-full p-2 rounded hover:bg-gray-400 cursor-pointer text-center py-5">
        <slot/>
    </RouterLink>
</template>

<script lang="ts">
import { ref, defineComponent } from 'vue'
import { RouterLink } from 'vue-router'
export default defineComponent({
  name: 'CatalogueSelector',
  components: {
      RouterLink
  },
  props: {
    name: {
      type: String,
      required: true
    }
  },
  setup: () => {

    //const router = useRouter()
    
    return {  }
  }
})
</script>

<style scoped>

</style>
